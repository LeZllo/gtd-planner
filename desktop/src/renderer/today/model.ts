import { useEffect, useMemo, useState } from 'react';
import { dayKey, deadlineInstant, idKey, sameID, supportsDailyRecurrence, todayScheduleSnapshot, type GTDDatabase, type GTDTask } from '../../domain';

export type TodaySnapshot = ReturnType<typeof todayScheduleSnapshot>;
export type PlanBlock = TodaySnapshot['planBlocks'][number];
export type Selection = { lane: 'plan' | 'actual'; start: string; end: string; startMinute: number; endMinute: number };
export type Mutation = (recipe: (db: GTDDatabase) => GTDDatabase) => string | null;
export type DrawerFilter = 'all' | 'progress' | 'complete-within' | 'overdue';
export const drawerLabels: Record<DrawerFilter, string> = { all: '待安排', progress: '跨日推进', 'complete-within': '区间内完成', overdue: '逾期' };
export const completedOn = (task: GTDTask, day: string) => task.status === 'done' || task.status === 'cancelled' || (supportsDailyRecurrence(task) && task.completedInstances.includes(day));
export const clockLabel = (value: string) => new Date(value).toLocaleTimeString('zh-CN', { hour: '2-digit', minute: '2-digit', hour12: false });
export { inputDateTime } from './drafts';
export const wholeMinutes = (seconds: number) => Math.floor(Math.max(0, seconds) / 60);
export const durationLabel = (seconds: number) => { const minutes = wholeMinutes(seconds); return minutes >= 60 ? `${Math.floor(minutes / 60)} 小时 ${minutes % 60} 分` : `${minutes} 分钟`; };
export const rangeLabel = (start: string, end: string) => `${clockLabel(start)} – ${dayKey(new Date(start)) === dayKey(new Date(end)) ? '' : '次日 '}${clockLabel(end)}`;
export const formatClock = (seconds: number) => { const total = Math.max(0, Math.floor(seconds)); return `${String(Math.floor(total / 3600)).padStart(2, '0')}:${String(Math.floor(total % 3600 / 60)).padStart(2, '0')}:${String(total % 60).padStart(2, '0')}`; };

/** The full projection is invalidated at the next exact deadline, never each timer tick. */
export function useTodaySnapshot(database: GTDDatabase | null, workspaceID: string, day: string) {
  const [deadlineRevision, setDeadlineRevision] = useState(0);
  const computed = useMemo(() => {
    const at = new Date();
    return { at: at.getTime(), snapshot: database ? todayScheduleSnapshot(database, workspaceID, day, at) : null };
  }, [database, workspaceID, day, deadlineRevision]);
  useEffect(() => {
    if (!database) return;
    const delay = nextDeadlineDelay(database.tasks, workspaceID, day, computed.at, Date.now());
    if (delay === null) return;
    const timer = window.setTimeout(() => setDeadlineRevision(value => value + 1), delay);
    return () => window.clearTimeout(timer);
  }, [database, workspaceID, day, computed]);
  return computed.snapshot;
}

export function nextDeadlineDelay(tasks: GTDTask[], workspaceID: string, day: string, projectedAt: number, now: number) {
  const next = tasks.reduce((nearest, task) => {
    if (!sameID(task.workspaceID, workspaceID) || completedOn(task, day)) return nearest;
    const deadline = deadlineInstant(task);
    // A deadline can cross between render and effect; compare against the
    // projection instant so that boundary still receives an immediate refresh.
    return deadline !== null && deadline >= projectedAt ? Math.min(nearest, deadline + 1) : nearest;
  }, Infinity);
  return Number.isFinite(next) ? Math.min(2_147_483_647, Math.max(1, next - now)) : null;
}

export function drawerTasks(snapshot: TodaySnapshot, filter: DrawerFilter) {
  if (filter === 'all') return snapshot.drawerTasks;
  const ids = new Set((filter === 'progress' ? snapshot.crossDayProgressTasks : filter === 'complete-within' ? snapshot.completeWithinTasks : snapshot.overdueTasks).map(task => idKey(task.id)));
  return snapshot.drawerTasks.filter(task => ids.has(idKey(task.id)));
}
