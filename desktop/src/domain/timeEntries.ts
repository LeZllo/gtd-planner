import { dayBounds } from './dates.js';
import { sameID } from './validation.js';
import type { TimeEntry } from './types.js';

/** Finished actual focus only; plans and the currently running timer are excluded.
 * Legacy timers store total active seconds, not pause segments. Crossing-day
 * sessions are therefore prorated by their elapsed overlap, preserving totals. */
export function actualFocusForDay(entries: readonly TimeEntry[], workspaceID: string, day: string): { seconds: number; estimated: boolean } {
  const [dayStart, dayEnd] = dayBounds(day);
  let seconds = 0;
  let estimated = false;
  for (const entry of entries) {
    if (!sameID(entry.workspaceID, workspaceID)) continue;
    const start = Date.parse(entry.startedAt), end = Date.parse(entry.endedAt);
    const overlap = Math.min(end, dayEnd) - Math.max(start, dayStart);
    if (!(end > start) || !(overlap > 0)) continue;
    if (entry.activeSeconds == null) seconds += overlap / 1000;
    else {
      seconds += Math.max(0, entry.activeSeconds) * overlap / (end - start);
      if (start < dayStart || end > dayEnd) estimated = true;
    }
  }
  return { seconds, estimated };
}
