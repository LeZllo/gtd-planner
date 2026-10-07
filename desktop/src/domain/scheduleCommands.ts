import type { GTDDatabase, GTDTask, TaskPlan } from './types.js';
import { canScheduleTaskOnDay, dateDay, dayBounds, dayKey, isDayKey, isISO, isMultiDayPlan, localDate, supportsDailyRecurrence } from './dates.js';
import { updateTask } from './operations.js';
import { emptyPlan, resolveTaskArrangements, taskPlan, type ArrangementRef } from './scheduling.js';
import { sameID, validateDatabase } from './validation.js';

export type ScheduleScope = 'occurrence' | 'future';
function workspaceTask(db: GTDDatabase, workspaceID: string, taskID: string): GTDTask {
  if (!db.workspaces.some(item => sameID(item.id, workspaceID))) throw new Error('Workspace was not found');
  const task = db.tasks.find(item => sameID(item.id, taskID));
  if (!task) throw new Error('Task was not found');
  if (!sameID(task.workspaceID, workspaceID)) throw new Error('Task belongs to another workspace');
  return task;
}
export interface SaveArrangementInput {
  workspaceID: string; taskID: string; day: string; ref: ArrangementRef | 'additional';
  plan: TaskPlan; scope?: ScheduleScope; expected?: TaskPlan;
}
export function saveTaskArrangement(db: GTDDatabase, input: SaveArrangementInput, now = new Date()): GTDDatabase {
  const task = workspaceTask(db, input.workspaceID, input.taskID), { day, ref } = input;
  dayBounds(day);
  const current = ref === 'additional' ? undefined : resolveTaskArrangements(task, day).find(item => item.source === ref.source && (item.source === 'taskPlan' || sameID(item.slotID, ref.slotID)));
  const plan: TaskPlan = { ...current?.plan, ...taskPlan(input.plan) };
  if (input.ref !== 'additional' && input.ref.source === 'executionSlot' && !current) throw new Error('此安排已被移除，请重新打开');
  if (input.expected && JSON.stringify(taskPlan(current?.plan || emptyPlan())) !== JSON.stringify(taskPlan(input.expected))) throw new Error('此安排已更新，请重新打开后修改');
  if (current && JSON.stringify(taskPlan(current.plan)) === JSON.stringify(taskPlan(plan))) return db;
  if (!['none', 'date', 'minute'].includes(plan.plannedPrecision) || !['progress', 'complete-within'].includes(plan.planRangeIntent) || (plan.plannedPrecision === 'none') !== !plan.plannedStart || (plan.plannedEnd && !plan.plannedStart)) throw new Error('安排日期与精度不一致');
  for (const value of [plan.plannedStart, plan.plannedEnd]) if (value && !(isISO(value) || (plan.plannedPrecision === 'date' && isDayKey(value)))) throw new Error('安排日期格式无效');
  if (plan.plannedStart && plan.plannedEnd && localDate(plan.plannedEnd) < localDate(plan.plannedStart)) throw new Error('结束不能早于开始');
  if (task.status === 'done' || task.status === 'cancelled') throw new Error('Finished tasks cannot be scheduled');
  const daily = supportsDailyRecurrence(task);
  if (ref !== 'additional' && ref.source === 'taskPlan') {
    if (task.recurrence.trim() && !daily) throw new Error('此重复规则只保留原文，暂不支持修改模板；可单独添加时段');
    let patch: Partial<GTDTask>;
    if (daily) {
      if (!canScheduleTaskOnDay(task, day)) throw new Error('This daily occurrence is completed, skipped, or before the recurrence starts');
      if (input.scope !== 'occurrence' && input.scope !== 'future') throw new Error('请选择仅本次或本次及以后');
      if (input.scope === 'future' && task.taskSchedule?.endsBefore && day >= task.taskSchedule.endsBefore) throw new Error('自动模板已停止；可单独修改本次，不会静默恢复以后重复');
      if (input.scope === 'future' && day < dayKey(now)) throw new Error('不能从过去日期重写后续模板，请选择今天或未来日期');
      if (plan.plannedStart && dateDay(plan.plannedStart) !== day) throw new Error('重复安排的日期须为当前实例日期；调整时间或为别的日期添加独立时段');
      if (isMultiDayPlan(plan)) throw new Error('重复任务的跨日窗口存在歧义，原数据保留；请使用单日安排或独立时段');
      const schedule = task.taskSchedule || { version: 1 as const, exceptions: [], revisions: [] };
      patch = { taskSchedule: input.scope === 'occurrence'
        ? { ...schedule, exceptions: [...schedule.exceptions.filter(item => item.day !== day), { ...schedule.exceptions.find(item => item.day === day), day, plan }].sort((a, b) => a.day.localeCompare(b.day)) }
        : { ...schedule, revisions: [...schedule.revisions.filter(item => item.fromDay !== day), { ...schedule.revisions.find(item => item.fromDay === day), fromDay: day, plan }].sort((a, b) => a.fromDay.localeCompare(b.fromDay)) } };
      // Future revisions preserve explicit occurrence exceptions, including this date.
      if (input.scope === 'future' && schedule.exceptions.some(item => item.day === day)) throw new Error('此日已有单次例外。请仅修改本次，或从没有例外的日期修改以后模板');
    } else patch = { ...plan };
    // Equal-instant legacy aliases represent one visible intent. Updating that
    // intent updates its alias atomically; unrelated sessions are never touched.
    if (current?.linkedSlotIDs.length) patch.executionSlots = task.executionSlots.flatMap(slot => {
      if (!current.linkedSlotIDs.some(id => sameID(id, slot.id))) return [slot];
      return plan.plannedPrecision === 'minute' && plan.plannedStart && plan.plannedEnd && Date.parse(plan.plannedEnd) > Date.parse(plan.plannedStart)
        ? [{ ...slot, start: plan.plannedStart, end: plan.plannedEnd }] : [];
    });
    return updateTask(db, task.id, patch, now);
  }
  // Slots are always explicit ranges, even when they cross local midnight.
  if (plan.plannedPrecision !== 'minute' || !plan.plannedStart || !plan.plannedEnd || Date.parse(plan.plannedEnd) <= Date.parse(plan.plannedStart)) throw new Error('独立时段需要有效的具体开始和结束时间');
  if (daily) {
    let cursor = dayBounds(dateDay(plan.plannedStart))[0];
    while (cursor < Date.parse(plan.plannedEnd)) {
      const key = dayKey(new Date(cursor));
      if (!canScheduleTaskOnDay(task, key)) throw new Error('This daily occurrence is completed, skipped, or before the recurrence starts');
      cursor = dayBounds(key)[1];
    }
  }
  if (ref === 'additional' && resolveTaskArrangements(task, day).some(item => item.plan.plannedPrecision === 'minute' && (item.source === 'executionSlot' || !isMultiDayPlan(item.plan)) && Date.parse(item.plan.plannedStart!) === Date.parse(plan.plannedStart!) && Date.parse(item.plan.plannedEnd!) === Date.parse(plan.plannedEnd!))) return db;
  const executionSlots = ref === 'additional'
    ? [...task.executionSlots, { id: crypto.randomUUID(), start: plan.plannedStart, end: plan.plannedEnd }]
    : task.executionSlots.map(slot => sameID(slot.id, ref.slotID) ? { ...slot, start: plan.plannedStart!, end: plan.plannedEnd! } : slot);
  return updateTask(db, task.id, { executionSlots }, now);
}
export function removeTaskArrangement(db: GTDDatabase, input: Omit<SaveArrangementInput, 'plan' | 'ref'> & { ref: ArrangementRef }, now = new Date()): GTDDatabase {
  if (input.ref.source === 'taskPlan') return saveTaskArrangement(db, { ...input, plan: emptyPlan() }, now);
  const task = workspaceTask(db, input.workspaceID, input.taskID);
  const current = resolveTaskArrangements(task, input.day).find(item => sameID(item.slotID, input.ref.slotID));
  if (!current) return db;
  if (input.expected && JSON.stringify(taskPlan(current.plan)) !== JSON.stringify(taskPlan(input.expected))) throw new Error('此安排已更新，请重新打开后修改');
  return updateTask(db, task.id, { executionSlots: task.executionSlots.filter(slot => !sameID(slot.id, input.ref.slotID)) }, now);
}
export function setTaskDeadline(db: GTDDatabase, workspaceID: string, taskID: string, deadline: string | null, precision: GTDTask['deadlinePrecision'], expected?: Pick<GTDTask, 'deadline' | 'deadlinePrecision'>): GTDDatabase {
  const task = workspaceTask(db, workspaceID, taskID);
  if (expected && (expected.deadline !== task.deadline || expected.deadlinePrecision !== task.deadlinePrecision)) throw new Error('截止已更新，请重新打开后修改');
  if ((task.deadline ?? null) === deadline && task.deadlinePrecision === precision) return db;
  if ((precision === 'none') !== !deadline) throw new Error('截止日期和精度不一致');
  return updateTask(db, task.id, { deadline, deadlinePrecision: precision });
}
/** Start/stop the supported daily template prospectively, without rewriting history. */
export function setDailyRecurrence(db: GTDDatabase, workspaceID: string, taskID: string, fromDay: string, enabled: boolean, now = new Date()): GTDDatabase {
  const task = workspaceTask(db, workspaceID, taskID);
  dayBounds(fromDay);
  if (fromDay < dayKey(now)) throw new Error('重复设置从今天或未来日期生效，历史保留');
  if (task.status === 'done' || task.status === 'cancelled') throw new Error('Finished tasks cannot be scheduled');
  if (enabled) {
    if (task.recurrence.trim()) throw new Error('现有重复规则已保留，请勿覆盖；停止后的模板可撤销本次更改');
    if (isMultiDayPlan(task)) throw new Error('跨日窗口不能直接变成每日重复；请先明确为单日安排');
    if (task.plannedStart && dateDay(task.plannedStart) > fromDay) throw new Error('重复开始日不能早于当前安排日期');
    return updateTask(db, task.id, { recurrence: 'FREQ=DAILY', ...(task.plannedStart ? {} : { plannedStart: fromDay, plannedPrecision: 'date' as const }), taskSchedule: { version: 1, startsOn: fromDay, exceptions: [], revisions: [] } }, now);
  }
  if (!supportsDailyRecurrence(task)) throw new Error('此重复规则不支持编辑，原文保留');
  const schedule = task.taskSchedule || { version: 1 as const, exceptions: [], revisions: [] };
  if (schedule.endsBefore === fromDay) return db;
  if (schedule.endsBefore) throw new Error('模板已停止；使用撤销恢复上次设置，避免重写历史');
  return updateTask(db, task.id, { taskSchedule: { ...schedule, endsBefore: fromDay } }, now);
}
const timeFields = ['plannedStart', 'plannedEnd', 'plannedPrecision', 'planRangeIntent', 'executionSlots', 'taskSchedule', 'deadline', 'deadlinePrecision', 'recurrence'] as const;
export function timeState(task: GTDTask) { return Object.fromEntries(timeFields.filter(key => Object.hasOwn(task, key)).map(key => [key, task[key]])); }
/** Undo only this task's time fields, never later unrelated task/actual/history edits. */
export function undoTaskTimeChange(db: GTDDatabase, before: GTDTask, after: GTDTask): GTDDatabase {
  const task = workspaceTask(db, before.workspaceID, before.id);
  if (JSON.stringify(timeState(task)) !== JSON.stringify(timeState(after))) throw new Error('时间设置已有后续修改，不能覆盖；请重新打开查看');
  const restored = { ...task, updatedAt: new Date().toISOString() };
  for (const key of timeFields) delete restored[key];
  Object.assign(restored, timeState(before));
  return validateDatabase({ ...db, tasks: db.tasks.map(item => sameID(item.id, task.id) ? restored : item) }).database;
}
