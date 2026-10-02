import assert from 'node:assert/strict';
import test from 'node:test';
import { emptyDatabase, createTask, updateTimeEntry, type ActiveTimer, type TimeEntry } from '../src/domain/index.js';
import { buildActualEntryPatch, inputDateTime, preferredSchedulableTaskID, resolveActualDraftRange, usesFineSnap, visibleTimerInterval } from '../src/renderer/today/drafts.js';

import { durationLabel, nextDeadlineDelay, wholeMinutes } from '../src/renderer/today/model.js';

function withTimezone<T>(timezone: string, run: () => T): T {
  const previous = process.env.TZ; process.env.TZ = timezone;
  try { return run(); } finally { if (previous === undefined) delete process.env.TZ; else process.env.TZ = previous; }
}

test('actual draft preserves unchanged sub-minute timestamps before validation', () => withTimezone('UTC', () => {
  const start = '2026-10-02T06:00:10.123+00:00', end = '2026-10-02T06:00:40.789+00:00';
  assert.equal(inputDateTime(start), inputDateTime(end));
  assert.deepEqual(resolveActualDraftRange(inputDateTime(start), inputDateTime(end), start, end), { startedAt: start, endedAt: end });
  assert.equal(resolveActualDraftRange('2026-10-02T07:00', inputDateTime(end), start, end), null);
}));

test('actual draft preserves repeated DST-hour instants although wall-clock end is earlier', () => withTimezone('America/New_York', () => {
  const start = '2026-11-01T01:50:12-04:00', end = '2026-11-01T01:10:42-05:00';
  assert.ok(inputDateTime(start) > inputDateTime(end));
  assert.deepEqual(resolveActualDraftRange(inputDateTime(start), inputDateTime(end), start, end), { startedAt: start, endedAt: end });
}));

test('metadata-only save retains raw timestamps and paused active seconds', () => withTimezone('UTC', () => {
  const db = emptyDatabase(), workspaceID = db.workspaces[0].id;
  const entry: TimeEntry = { id: crypto.randomUUID(), workspaceID, taskID: null, title: 'Short focus', startedAt: '2026-10-02T06:00:10.123+00:00', endedAt: '2026-10-02T06:00:40.789+00:00', activeSeconds: 11, source: 'stopwatch', note: '' };
  db.timeEntries.push(entry);
  const range = resolveActualDraftRange(inputDateTime(entry.startedAt), inputDateTime(entry.endedAt), entry.startedAt, entry.endedAt)!;
  const next = updateTimeEntry(db, workspaceID, entry.id, { ...range, note: 'Changed note' }, new Date('2026-10-02T07:00:00Z'));
  assert.equal(next.timeEntries[0].startedAt, entry.startedAt);
  assert.equal(next.timeEntries[0].endedAt, entry.endedAt);
  assert.equal(next.timeEntries[0].activeSeconds, 11);
  assert.equal(next.timeEntries[0].source, 'stopwatch');
  assert.equal(next.timeEntries[0].note, 'Changed note');
}));

test('actual draft changes only the edited bound and rejects invalid times', () => withTimezone('UTC', () => {
  const start = '2026-10-02T05:30:11.123Z', end = '2026-10-02T06:30:44.456Z';
  assert.deepEqual(resolveActualDraftRange(inputDateTime(start), '2026-10-02T06:40', start, end), { startedAt: start, endedAt: '2026-10-02T06:40:00.000Z' });
  assert.equal(resolveActualDraftRange('', inputDateTime(end), start, end), null);
}));

function timer(workspaceID: string, overrides: Partial<ActiveTimer> = {}): ActiveTimer {
  return { mode: 'pomodoro', workspaceID, taskID: null, title: 'Focus', sessionStartedAt: '2026-10-01T23:00:00Z', startedAt: '2026-10-01T23:00:00Z', accumulatedSeconds: 0, targetSeconds: 1500, focusCount: 0, ...overrides };
}

test('paused-before-day and exact-midnight-ended timers have no Today overlay', () => withTimezone('UTC', () => {
  for (const pausedAt of ['2026-10-01T23:50:00Z', '2026-10-02T00:00:00Z']) assert.equal(visibleTimerInterval(timer('work', { pausedAt }), [], 'work', '2026-10-02', new Date('2026-10-02T09:00:00Z')), null);
}));

test('live overlay clips active interval and resolves mixed-case task workspace', () => withTimezone('UTC', () => {
  let db = emptyDatabase(); const workspaceID = db.workspaces[0].id;
  db = createTask(db, { workspaceID, title: 'Linked task' }); const task = db.tasks[0];
  const active = timer(workspaceID, { workspaceID: null, taskID: task.id.toUpperCase(), pausedAt: '2026-10-02T01:00:00Z' });
  assert.deepEqual(visibleTimerInterval(active, db.tasks, workspaceID.toUpperCase(), '2026-10-02', new Date('2026-10-02T09:00:00Z')), { start: '2026-10-02T00:00:00.000Z', end: '2026-10-02T01:00:00.000Z' });
  assert.equal(visibleTimerInterval(active, db.tasks, crypto.randomUUID(), '2026-10-02', new Date('2026-10-02T09:00:00Z')), null);
  assert.equal(visibleTimerInterval(timer(workspaceID, { workspaceID: null }), [], workspaceID, '2026-10-02', new Date('2026-10-02T09:00:00Z')), null);
}));

test('unchanged imported actual draft is a strict no-op, preserving absent keys and raw title', () => withTimezone('UTC', () => {
  for (const title of ['  Focus  ', '']) {
    const db = emptyDatabase(), workspaceID = db.workspaces[0].id;
    const entry: TimeEntry = { id: crypto.randomUUID(), workspaceID, title, startedAt: '2026-10-02T06:00:10.123+00:00', endedAt: '2026-10-02T06:00:40.789+00:00', activeSeconds: 11, source: 'stopwatch', note: '', custom: { preserved: true } };
    db.timeEntries.push(entry);
    const draft = { start: inputDateTime(entry.startedAt), end: inputDateTime(entry.endedAt), title, note: '', taskID: '' };
    const patch = buildActualEntryPatch(entry, draft)!;
    assert.deepEqual(patch, {});
    assert.equal(updateTimeEntry(db, workspaceID, entry.id, patch, new Date('2026-10-02T07:00:00Z')), db);
    const notePatch = buildActualEntryPatch(entry, { ...draft, note: 'New note' })!;
    assert.deepEqual(notePatch, { note: 'New note' });
    const next = updateTimeEntry(db, workspaceID, entry.id, notePatch, new Date('2026-10-02T07:00:00Z'));
    assert.equal(next.timeEntries[0].title, title);
    assert.equal(Object.hasOwn(next.timeEntries[0], 'taskID'), false);
    assert.equal(next.timeEntries[0].custom, entry.custom);
    assert.equal(next.timeEntries[0].activeSeconds, 11);
  }
}));

test('deadline invalidation picks exact nearest boundary, including render/effect race', () => withTimezone('UTC', () => {
  let db = emptyDatabase(); const workspaceID = db.workspaces[0].id;
  db = createTask(db, { workspaceID, title: 'Deadline' });
  const task = { ...db.tasks[0], workspaceID: workspaceID.toUpperCase(), deadline: '2026-10-02T07:00:00Z', deadlinePrecision: 'minute' as const };
  const deadline = Date.parse(task.deadline);
  assert.equal(nextDeadlineDelay([task], workspaceID, '2026-10-02', deadline - 1000, deadline - 1000), 1001);
  assert.equal(nextDeadlineDelay([task], workspaceID, '2026-10-02', deadline - 1, deadline + 10), 1);
  assert.equal(nextDeadlineDelay([task], workspaceID, '2026-10-02', deadline + 1, deadline + 10), null);
  assert.equal(nextDeadlineDelay([{ ...task, status: 'done' }], workspaceID, '2026-10-02', deadline - 1, deadline - 1), null);
}));

test('actual editor discards stale, completed, skipped, or foreign preferred task IDs', () => {
  let db = emptyDatabase(); const workspaceID = db.workspaces[0].id;
  db = createTask(db, { workspaceID, title: 'Daily' });
  const task = { ...db.tasks[0], recurrence: 'RRULE:FREQ=DAILY', plannedStart: '2026-10-01', plannedPrecision: 'date' as const };
  assert.equal(preferredSchedulableTaskID([task], workspaceID, '2026-10-02', task.id.toUpperCase()), task.id);
  assert.equal(preferredSchedulableTaskID([{ ...task, completedInstances: ['2026-10-02'] }], workspaceID, '2026-10-02', task.id), '');
  assert.equal(preferredSchedulableTaskID([{ ...task, skippedInstances: ['2026-10-02'] }], workspaceID, '2026-10-02', task.id), '');
  assert.equal(preferredSchedulableTaskID([{ ...task, status: 'done' }], workspaceID, '2026-10-02', task.id), '');
  assert.equal(preferredSchedulableTaskID([task], crypto.randomUUID(), '2026-10-02', task.id), '');
  assert.equal(preferredSchedulableTaskID([task], workspaceID, '2026-10-02', crypto.randomUUID()), '');
});

test('Today aggregate and list duration displays consistently truncate partial minutes', () => {
  const totals = [0, 59.999, 60, 2810.5, 3599.999, 3600, 3661.25];
  assert.deepEqual(totals.map(wholeMinutes), [0, 0, 1, 46, 59, 60, 61]);
  assert.equal(durationLabel(2810.5), '46 分钟');
  assert.equal(durationLabel(3599.999), '59 分钟');
  assert.equal(durationLabel(3600), '1 小时 0 分');
  assert.equal(durationLabel(3661.25), '1 小时 1 分');
  // Aggregate raw seconds before formatting; never sum truncated entry labels.
  assert.equal(wholeMinutes(59.5 + 59.5), 1);
  assert.equal(totals[3], 2810.5);
});

test('fine snap accepts Alt/Option or Shift and keeps ordinary dragging coarse', () => {
  assert.equal(usesFineSnap({ altKey: false, shiftKey: false }), false);
  assert.equal(usesFineSnap({ altKey: true, shiftKey: false }), true);
  assert.equal(usesFineSnap({ altKey: false, shiftKey: true }), true);
  assert.equal(usesFineSnap({ altKey: true, shiftKey: true }), true);
});
