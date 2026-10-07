import { idKey, type GTDTask } from '../domain';

/** Linear lookup after create/duplicate; never scans the old task array per candidate. */
export function firstAddedTask(previous: GTDTask[], next: GTDTask[]) {
  const existing = new Set(previous.map(task => idKey(task.id)));
  return next.find(task => !existing.has(idKey(task.id)));
}

/** Cached locale formatter with explicit invalidation for device timezone changes. */
let timeFormatter: Intl.DateTimeFormat | undefined;
export function resetTimeFormatter() { timeFormatter = undefined; }
export function formatTime(value: string) {
  const date = new Date(value);
  if (!Number.isFinite(date.getTime())) return 'Invalid Date';
  timeFormatter ??= new Intl.DateTimeFormat('zh-CN', { hour: '2-digit', minute: '2-digit', hour12: false });
  return timeFormatter.format(date);
}
