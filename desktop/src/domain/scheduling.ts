import type { GTDTask, TaskPlan } from './types.js';
import { dailyTemplateActive, dateDay, dayBounds, dayKey, isMultiDayPlan, localDate, supportsDailyRecurrence, taskPlanIntersectsDay, wallClockTime } from './dates.js';

export interface ArrangementRef { source: 'taskPlan' | 'executionSlot'; slotID?: string }
export interface TaskArrangement extends ArrangementRef {
  id: string; plan: TaskPlan; linkedSlotIDs: string[];
}
export const taskPlan = (task: TaskPlan): TaskPlan => ({ plannedStart: task.plannedStart, plannedEnd: task.plannedEnd, plannedPrecision: task.plannedPrecision, planRangeIntent: task.planRangeIntent });
export const emptyPlan = (): TaskPlan => ({ plannedStart: null, plannedEnd: null, plannedPrecision: 'none', planRangeIntent: 'progress' });
export function shiftPlan(plan: TaskPlan, day: string): TaskPlan {
  if (!plan.plannedStart || isMultiDayPlan(plan)) return plan;
  const anchorDay = dateDay(plan.plannedStart);
  if (day === anchorDay) return plan; // Preserve offsets, seconds and fold choice on its original day.
  const ordinal = (key: string) => { const date = localDate(key); const utc = new Date(0); utc.setUTCFullYear(date.getFullYear(), date.getMonth(), date.getDate()); utc.setUTCHours(0, 0, 0, 0); return utc.getTime() / 86_400_000; };
  const offset = ordinal(day) - ordinal(anchorDay);
  const shift = (value: string) => {
    const source = localDate(value), target = localDate(dateDay(value)); target.setDate(target.getDate() + offset);
    if (plan.plannedPrecision === 'date') return dayKey(target);
    return wallClockTime(dayKey(target), source.getHours() * 60 + source.getMinutes() + source.getSeconds() / 60 + source.getMilliseconds() / 60_000).toISOString();
  };
  const start = shift(plan.plannedStart); let end = plan.plannedEnd ? shift(plan.plannedEnd) : plan.plannedEnd;
  if (plan.plannedPrecision === 'minute' && end && Date.parse(end) <= Date.parse(start) && plan.plannedEnd && Date.parse(plan.plannedEnd) > Date.parse(plan.plannedStart)) {
    end = new Date(Date.parse(start) + Date.parse(plan.plannedEnd) - Date.parse(plan.plannedStart)).toISOString();
  }
  return { ...plan, plannedStart: start, plannedEnd: end };
}
/** Exception > effective template revision > original legacy template. */
export function effectiveTaskPlan(task: GTDTask, day?: string): TaskPlan {
  if (!day || !supportsDailyRecurrence(task)) return taskPlan(task);
  const exception = task.taskSchedule?.exceptions.find(item => item.day === day);
  if (exception) return exception.plan;
  if (task.taskSchedule?.endsBefore && day >= task.taskSchedule.endsBefore) return emptyPlan();
  if (task.taskSchedule?.startsOn && day < task.taskSchedule.startsOn) return taskPlan(task);
  let plan = taskPlan(task), from = '';
  for (const revision of task.taskSchedule?.revisions || []) if (revision.fromDay <= day && revision.fromDay > from) { plan = revision.plan; from = revision.fromDay; }
  return task.plannedStart && day < dateDay(task.plannedStart) ? plan : shiftPlan(plan, day);
}
export function isConcretePlan(plan: TaskPlan): boolean {
  return plan.plannedPrecision === 'minute' && !!plan.plannedStart && !isMultiDayPlan(plan);
}
/** Match before clipping. Equal visible portions of different cross-day ranges are NOT aliases. */
export function resolveTaskArrangements(task: GTDTask, day?: string): TaskArrangement[] {
  const plan = effectiveTaskPlan(task, day), result: TaskArrangement[] = [];
  const alias = isConcretePlan(plan) && plan.plannedEnd && Date.parse(plan.plannedEnd) > Date.parse(plan.plannedStart!)
    ? task.executionSlots.find(slot => Date.parse(slot.start) === Date.parse(plan.plannedStart!) && Date.parse(slot.end) === Date.parse(plan.plannedEnd!)) : undefined;
  if (plan.plannedStart && plan.plannedPrecision !== 'none') result.push({ id: `${task.id}:plan`, source: 'taskPlan', plan, linkedSlotIDs: alias ? [alias.id] : [] });
  for (const slot of task.executionSlots) if (slot !== alias) result.push({ id: `${task.id}:slot:${slot.id}`, source: 'executionSlot', slotID: slot.id, plan: { plannedStart: slot.start, plannedEnd: slot.end, plannedPrecision: 'minute', planRangeIntent: 'progress' }, linkedSlotIDs: [] });
  return result;
}
export function arrangementWarnings(task: GTDTask, day?: string): string[] {
  const arrangements = resolveTaskArrangements(task, day), warnings: string[] = [];
  if (day && task.taskSchedule?.exceptions.some(row => row.day === day && row.plan.plannedStart && dateDay(row.plan.plannedStart) !== day)) warnings.push('此单次安排的具体时间落在其他本地日期，可能来自时区变化。原始时间已保留，请核对后编辑');
  if (arrangements.some(item => item.linkedSlotIDs.length)) warnings.push('相同的旧计划与执行时段按一项安排显示和累计；原始记录仍保留，修改时同步这两个表示');
  const concrete = arrangements.filter(item => item.source === 'executionSlot' || isConcretePlan(item.plan))
    .map(item => ({ start: Date.parse(item.plan.plannedStart!), end: Date.parse(item.plan.plannedEnd || item.plan.plannedStart!) }))
    .sort((a, b) => a.start - b.start);
  let latestEnd = -Infinity;
  for (const item of concrete) {
    if (item.start < latestEnd) { warnings.push('存在不同的重叠安排，已分别保留并累计；请核对后再修改，不会自动合并'); break; }
    latestEnd = Math.max(latestEnd, item.end);
  }
  return warnings;
}
export function arrangementEnd(plan: TaskPlan): number | null {
  if (!plan.plannedStart || plan.plannedPrecision === 'none') return null;
  return plan.plannedPrecision === 'date' ? dayBounds(dateDay(plan.plannedEnd || plan.plannedStart))[1] : Date.parse(plan.plannedEnd || plan.plannedStart);
}
/** A missed plan is rescheduling work, never a deadline. Future slots keep a task scheduled. */
export function needsReschedule(task: GTDTask, day: string, now: Date): boolean {
  if (day !== dayKey(now) || task.status === 'done' || task.status === 'cancelled' || task.completedInstances.includes(day) || task.skippedInstances.includes(day)) return false;
  const plan = effectiveTaskPlan(task, day), daily = supportsDailyRecurrence(task);
  // A civil window covering today cannot have expired. Avoid constructing
  // thousands of local-midnight dates or arrangement objects for this common case.
  if (plan.plannedPrecision === 'date' && plan.plannedStart && dateDay(plan.plannedEnd || plan.plannedStart) >= day) return false;
  let latest = plan.plannedPrecision === 'date' && plan.plannedStart ? 0 : arrangementEnd(plan);
  let bounds: [number, number] | undefined;
  for (const slot of task.executionSlots) {
    const end = Date.parse(slot.end);
    if (daily) { bounds ||= dayBounds(day); if (end <= bounds[0] || Date.parse(slot.start) >= bounds[1]) continue; }
    if (end >= now.getTime()) return false;
    latest = Math.max(latest ?? -Infinity, end);
  }
  return latest !== null && latest < now.getTime();
}
