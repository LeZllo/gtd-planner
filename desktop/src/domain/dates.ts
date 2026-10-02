import type { GTDTask } from './types.js';

export function dayKey(date: Date): string {
  if (!Number.isFinite(date.getTime())) throw new Error('Invalid date');
  return `${String(date.getFullYear()).padStart(4, '0')}-${String(date.getMonth() + 1).padStart(2, '0')}-${String(date.getDate()).padStart(2, '0')}`;
}
export function isDayKey(value: unknown): value is string {
  if (typeof value !== 'string' || !/^\d{4}-\d{2}-\d{2}$/.test(value)) return false;
  const [y, m, d] = value.split('-').map(Number);
  const date = new Date(0); date.setUTCFullYear(y, m - 1, d); date.setUTCHours(0, 0, 0, 0);
  return y > 0 && date.getUTCFullYear() === y && date.getUTCMonth() === m - 1 && date.getUTCDate() === d;
}
export function isISO(value: unknown): value is string {
  if (typeof value !== 'string') return false;
  const match = /^(\d{4}-\d{2}-\d{2})T(\d{2}):(\d{2}):(\d{2})(?:\.\d{1,9})?(Z|[+-]\d{2}:\d{2})$/.exec(value);
  if (!match || !isDayKey(match[1]) || +match[2] > 23 || +match[3] > 59 || +match[4] > 59) return false;
  if (match[5] !== 'Z' && (+match[5].slice(1, 3) > 23 || +match[5].slice(4) > 59)) return false;
  return Number.isFinite(Date.parse(value));
}
/** Civil dates are never parsed as UTC. Legacy ISO dates use the device timezone,
 * matching Calendar.current. Legacy exports omit the originating timezone; it
 * cannot be recovered. Preserve the source string and warn rather than guessing. */
export function localDate(value: string): Date {
  if (isDayKey(value)) {
    const [y, m, d] = value.split('-').map(Number);
    const date = new Date(0); date.setFullYear(y, m - 1, d); date.setHours(0, 0, 0, 0); return date;
  }
  return new Date(value);
}
export function dateDay(value: string): string { return isDayKey(value) ? value : dayKey(localDate(value)); }
export function dayBounds(day: string): [number, number] {
  if (!isDayKey(day)) throw new Error('Day must be a valid YYYY-MM-DD local date');
  const start = localDate(day); const end = new Date(start); end.setDate(end.getDate() + 1);
  return [start.getTime(), end.getTime()];
}
export function isDailyRecurring(task: GTDTask): boolean {
  const parts = task.recurrence.trim().toUpperCase().replace(/^RRULE:/, '').split(';').map(p => p.trim());
  return parts.includes('FREQ=DAILY');
}
/** Only plain daily recurrence is projected. Keep other RRULEs without faking support. */
export function supportsDailyRecurrence(task: GTDTask): boolean {
  const parts = task.recurrence.trim().toUpperCase().replace(/^RRULE:/, '').split(';').filter(Boolean).map(p => p.trim());
  return parts.includes('FREQ=DAILY') && parts.every(p => p === 'FREQ=DAILY' || p === 'INTERVAL=1');
}

/** Date-only deadlines expire after their entire local civil day. */
export function deadlineInstant(task: GTDTask): number | null {
  if (!task.deadline) return null;
  return task.deadlinePrecision === 'date' ? dayBounds(dateDay(task.deadline))[1] : localDate(task.deadline).getTime();
}
export function isTaskCompletedOnDay(task: GTDTask, day: string): boolean {
  return supportsDailyRecurrence(task) ? task.completedInstances.includes(day)
    : task.status === 'done' && !!task.completedAt && dateDay(task.completedAt) === day;
}
export function canScheduleTaskOnDay(task: GTDTask, day: string): boolean {
  dayBounds(day);
  if (task.status === 'done' || task.status === 'cancelled') return false;
  if (!supportsDailyRecurrence(task)) return true;
  return !task.completedInstances.includes(day) && !task.skippedInstances.includes(day)
    && (!task.plannedStart || dateDay(task.plannedStart) <= day);
}
export function taskPlanIntersectsDay(task: GTDTask, day: string): boolean {
  if (!task.plannedStart) return false;
  if (task.plannedPrecision === 'date') return dateDay(task.plannedStart) <= day && day <= dateDay(task.plannedEnd ?? task.plannedStart);
  const [start, end] = dayBounds(day), a = localDate(task.plannedStart).getTime(), b = task.plannedEnd ? localDate(task.plannedEnd).getTime() : a;
  return b > a ? a < end && b > start : a >= start && a < end;
}
export function isMultiDayPlan(task: GTDTask): boolean {
  if (!task.plannedStart || !task.plannedEnd) return false;
  if (task.plannedPrecision === 'date') return dateDay(task.plannedStart) < dateDay(task.plannedEnd);
  return localDate(task.plannedEnd).getTime() > dayBounds(dateDay(task.plannedStart))[1];
}
/** ECMAScript's local-time conversion preserves smaller components in a DST
 * gap (02:30 -> 03:30) and chooses the first occurrence in a fall-back fold. */
export function wallClockTime(day: string, minute: number): Date {
  if (!Number.isFinite(minute) || minute < 0 || minute > 1440) throw new Error('Clock minute must be between 0 and 1440');
  const [start, end] = dayBounds(day);
  if (minute === 1440) return new Date(end);
  const date = new Date(start), whole = Math.floor(minute);
  date.setHours(Math.floor(whole / 60), whole % 60, 0, Math.round((minute - whole) * 60_000));
  return date;
}
