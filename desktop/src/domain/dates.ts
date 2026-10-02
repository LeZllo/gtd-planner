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
