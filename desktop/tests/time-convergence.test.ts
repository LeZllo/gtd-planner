import test from 'node:test';
import assert from 'node:assert/strict';
import { addExecutionSlot, arrangementWarnings, createTask, createWorkspace, demoDatabase, effectiveTaskPlan, emptyDatabase, exportDatabase, needsReschedule, parseImport, parseStoredDatabase, planBlocksForDay, removeExecutionSlot, removeTaskArrangement, resolveTaskArrangements, saveTaskArrangement, setTaskDeadline, taskPlan, tasksForDay, timeState, todayScheduleSnapshot, undoTaskTimeChange, updateTask, validateDatabase, type GTDDatabase, type GTDTask, type TaskPlan } from '../src/domain/index.js';
import { planDraft, resolvePlanDraft, withPlanDuration } from '../src/renderer/timeDrafts.js';
import { completeTask, setDailyRecurrence } from '../src/domain/index.js';
import { nextDeadlineDelay } from '../src/renderer/today/model.js';

const day = '2026-10-03', now = new Date(`${day}T12:00:00Z`), at = (hour: number, date = day) => `${date}T${String(hour).padStart(2, '0')}:00:00Z`;
const interval = (start = at(9), end = at(10)): TaskPlan => ({ plannedStart: start, plannedEnd: end, plannedPrecision: 'minute', planRangeIntent: 'progress' });
const slot = (start = at(9), end = at(10)) => ({ id: crypto.randomUUID(), start, end });
function fresh(patch: Partial<GTDTask> = {}) { let db = emptyDatabase(); db = createTask(db, { workspaceID: db.workspaces[0].id, title: 'Schedule test' }); db.tasks[0] = { ...db.tasks[0], ...patch }; return db; }
function input(db: GTDDatabase) { return { workspaceID: db.workspaces[0].id, taskID: db.tasks[0].id, day, ref: { source: 'taskPlan' as const } }; }
function zone<T>(tz: string, fn: () => T) { const old = process.env.TZ; process.env.TZ = tz; try { return fn(); } finally { if (old === undefined) delete process.env.TZ; else process.env.TZ = old; } }

test('legacy equal-instant aliases count once and raw JSON remains intact across import/export', () => zone('UTC', () => {
  const db = fresh({ ...interval(), executionSlots: [slot(`${day}T11:00:00+02:00`, `${day}T12:00:00+02:00`)] });
  const before = JSON.stringify(db), blocks = planBlocksForDay(db.tasks[0], day);
  assert.equal(blocks.length, 1); assert.equal(blocks[0].plannedDuration, 3600);
  assert.equal(todayScheduleSnapshot(db, db.workspaces[0].id, day, now).plannedDuration, 3600);
  const imported = parseImport(exportDatabase(db));
  assert.deepEqual(imported.database.tasks[0], JSON.parse(JSON.stringify(db.tasks[0]))); assert.equal(JSON.stringify(db), before);
  assert.ok(imported.warnings.some(warning => warning.includes('累计')));
}));
test('fixture double projection is fixed without changing the fictional source fixture', () => zone('UTC', () => {
  const db = demoDatabase(now), task = db.tasks.find(task => task.title === 'Outline the release announcement')!;
  assert.equal(task.executionSlots.length, 1); assert.ok(task.plannedStart);
  assert.equal(planBlocksForDay(task, day).length, 1); assert.equal(planBlocksForDay(task, day)[0].plannedDuration, 3600);
}));
test('overlap, distinct equal-bound slots and other-task plans retain their independent identities', () => zone('UTC', () => {
  const db = fresh({ ...interval(), executionSlots: [slot(), slot(), slot(at(9), at(11))] });
  const blocks = planBlocksForDay(db.tasks[0], day);
  assert.equal(blocks.length, 3); assert.equal(blocks.reduce((n, block) => n + block.plannedDuration, 0), 14400);
  assert.equal(db.tasks[0].executionSlots.length, 3); assert.equal(arrangementWarnings(db.tasks[0]).length, 2);
  assert.equal(planBlocksForDay({ ...db.tasks[0], id: crypto.randomUUID() }, day).length, 3);
}));
test('deduplication uses full bounds before clipping and never matches a cosmetic point footprint', () => zone('UTC', () => {
  const db = fresh({ plannedStart: at(23, '2026-10-02'), plannedEnd: at(0), plannedPrecision: 'minute', executionSlots: [slot(at(22, '2026-10-02'), at(1))] });
  assert.equal(planBlocksForDay(db.tasks[0], '2026-10-02').length, 2);
  const point = fresh({ plannedStart: at(9), plannedPrecision: 'minute', executionSlots: [slot(at(9), `${day}T09:30:00Z`)] });
  assert.equal(planBlocksForDay(point.tasks[0], day).length, 2); assert.equal(planBlocksForDay(point.tasks[0], day).find(block => block.isPoint)?.plannedDuration, 0);
}));
test('editing a linked legacy intent updates both aliases atomically, and removal does not reveal a ghost', () => zone('UTC', () => {
  const db = fresh({ ...interval(), executionSlots: [slot(), slot(at(15), at(16))] });
  const next = saveTaskArrangement(db, { ...input(db), plan: interval(at(10), at(11)), expected: taskPlan(db.tasks[0]) }, now);
  assert.equal(next.tasks[0].plannedStart, at(10)); assert.equal(next.tasks[0].executionSlots[0].start, at(10)); assert.deepEqual(next.tasks[0].executionSlots[1], db.tasks[0].executionSlots[1]);
  const removed = removeExecutionSlot(next, input(db).workspaceID, input(db).taskID, next.tasks[0].executionSlots[0].id);
  assert.equal(removed.tasks[0].plannedPrecision, 'none'); assert.equal(removed.tasks[0].executionSlots.length, 1); assert.equal(planBlocksForDay(removed.tasks[0], day).length, 1);
  const restored = undoTaskTimeChange(next, db.tasks[0], next.tasks[0]); assert.deepEqual(timeState(restored.tasks[0]), timeState(db.tasks[0]));
}));
test('point-to-range conversion creates one shared arrangement; repeated exact submit is a no-op', () => zone('UTC', () => {
  const db = fresh({ plannedStart: at(9), plannedPrecision: 'minute' });
  const next = saveTaskArrangement(db, { ...input(db), plan: interval(), expected: taskPlan(db.tasks[0]) }, now);
  assert.equal(planBlocksForDay(next.tasks[0], day).length, 1); assert.equal(planBlocksForDay(next.tasks[0], day)[0].plannedDuration, 3600);
  assert.equal(addExecutionSlot(next, { ...input(db), start: at(9), end: at(10) }, now), next);
}));
test('no-op plan drafts retain date precision, legacy ISO strings, seconds and DST fold instants', () => {
  for (const tz of ['UTC', 'America/New_York', 'Asia/Tokyo']) zone(tz, () => {
    for (const plan of [interval('2026-11-01T01:50:12.123-04:00', '2026-11-01T01:10:44.567-05:00'), { ...interval(), plannedStart: '2026-10-03', plannedEnd: '2026-10-05', plannedPrecision: 'date' as const }, { ...interval(), plannedPrecision: 'date' as const }]) assert.strictEqual(resolvePlanDraft(planDraft(plan), plan), plan);
  });
});
test('date edits never silently demote minute precision; unchanged bound retains original raw text', () => zone('UTC', () => {
  const original = interval(`${day}T09:00:12.123+00:00`, `${day}T10:00:44.567+00:00`), draft = planDraft(original);
  const plan = resolvePlanDraft({ ...draft, start: `${day}T09:15` }, original);
  assert.equal(plan.plannedPrecision, 'minute'); assert.equal(plan.plannedEnd, original.plannedEnd);
  assert.throws(() => resolvePlanDraft({ ...draft, start: '' }, original), /日期/);
  const date = resolvePlanDraft({ ...draft, precision: 'date', start: day, end: day }, original);
  assert.equal(date.plannedPrecision, 'date'); assert.equal(date.plannedStart, day);
}));
test('deadline editing is independent, minute precision survives, and missing empty deadline saves as no-op', () => zone('UTC', () => {
  const db = fresh({ ...interval(), deadline: `${day}T14:00:32+00:00`, deadlinePrecision: 'minute', executionSlots: [slot()] });
  const next = setTaskDeadline(db, input(db).workspaceID, input(db).taskID, `${day}T15:00:32+00:00`, 'minute');
  assert.deepEqual(taskPlan(next.tasks[0]), taskPlan(db.tasks[0])); assert.deepEqual(next.tasks[0].executionSlots, db.tasks[0].executionSlots);
  const blank = fresh(); assert.strictEqual(setTaskDeadline(blank, input(blank).workspaceID, input(blank).taskID, null, 'none'), blank);
}));
test('missed plans return today as needs-reschedule, separate from overdue, without changing historical membership', () => zone('UTC', () => {
  for (const plan of [interval(at(9, '2026-10-02'), at(10, '2026-10-02')), { ...interval(), plannedStart: '2026-10-02', plannedEnd: null, plannedPrecision: 'date' as const }, { ...interval(), plannedEnd: null }]) {
    const db = fresh({ ...plan }), snapshot = todayScheduleSnapshot(db, input(db).workspaceID, day, now);
    assert.equal(snapshot.tasks.length, 1); assert.equal(snapshot.rescheduleTasks.length, 1); assert.equal(snapshot.overdueCount, 0); assert.equal(snapshot.waitingCount, 1);
    assert.equal(tasksForDay(db, input(db).workspaceID, '2026-10-04', now).length, 0);
  }
  const future = fresh({ ...interval(), executionSlots: [slot(at(13), at(14))] }); assert.equal(needsReschedule(future.tasks[0], day, now), false);
  for (const status of ['done', 'cancelled'] as const) assert.equal(needsReschedule({ ...future.tasks[0], status }, day, now), false);
}));
test('arrangement expiry triggers one exact invalidation, not a per-second full projection', () => zone('UTC', () => {
  const db = fresh({ ...interval() }), boundary = Date.parse(at(10));
  assert.equal(nextDeadlineDelay(db.tasks, input(db).workspaceID, day, boundary - 1000, boundary - 1000), 1001);
  assert.equal(nextDeadlineDelay(db.tasks, input(db).workspaceID, day, boundary + 1, boundary + 10), null);
}));
test('cross-day intention windows count no work hours; explicit midnight/DST slots count real elapsed time', () => zone('America/New_York', () => {
  const db = fresh({ plannedStart: '2026-03-07', plannedEnd: '2026-03-09', plannedPrecision: 'date', planRangeIntent: 'complete-within', executionSlots: [slot('2026-03-08T00:00:00-05:00', '2026-03-09T00:00:00-04:00')] });
  const blocks = planBlocksForDay(db.tasks[0], '2026-03-08'); assert.equal(blocks.length, 1); assert.equal(blocks[0].plannedDuration, 23 * 3600);
  assert.equal(planBlocksForDay({ ...db.tasks[0], executionSlots: [] }, '2026-03-08').length, 0);
}));
test('daily occurrence edit leaves future template, earlier history and all completion tokens unchanged', () => zone('UTC', () => {
  const db = fresh({ ...interval(at(9, '2026-10-01'), at(10, '2026-10-01')), recurrence: 'FREQ=DAILY', completedInstances: ['2026-10-02'], skippedInstances: ['2026-10-05'] });
  const next = saveTaskArrangement(db, { ...input(db), plan: interval(at(11), at(12)), scope: 'occurrence' }, now);
  assert.equal(planBlocksForDay(next.tasks[0], day)[0].start, new Date(at(11)).toISOString());
  assert.equal(planBlocksForDay(next.tasks[0], '2026-10-04')[0].start, '2026-10-04T09:00:00.000Z');
  assert.deepEqual(taskPlan(next.tasks[0]), taskPlan(db.tasks[0])); assert.deepEqual(next.tasks[0].completedInstances, db.tasks[0].completedInstances); assert.deepEqual(next.tasks[0].skippedInstances, db.tasks[0].skippedInstances);
}));
test('future template revision is effective-dated and preserves prior and later explicit exceptions/revisions', () => zone('UTC', () => {
  const db = fresh({ ...interval(at(9, '2026-10-01'), at(10, '2026-10-01')), recurrence: 'FREQ=DAILY', taskSchedule: { version: 1, exceptions: [{ day: '2026-10-04', plan: interval(at(15, '2026-10-04'), at(16, '2026-10-04')) }], revisions: [{ fromDay: '2026-10-06', plan: interval(at(8, '2026-10-06'), at(9, '2026-10-06')) }] } });
  const next = saveTaskArrangement(db, { ...input(db), plan: interval(at(11), at(12)), scope: 'future' }, now);
  assert.equal(effectiveTaskPlan(next.tasks[0], '2026-10-02').plannedStart, '2026-10-02T09:00:00.000Z');
  assert.equal(effectiveTaskPlan(next.tasks[0], '2026-10-04').plannedStart, at(15, '2026-10-04'));
  assert.equal(effectiveTaskPlan(next.tasks[0], '2026-10-05').plannedStart, '2026-10-05T11:00:00.000Z');
  assert.equal(effectiveTaskPlan(next.tasks[0], '2026-10-06').plannedStart, at(8, '2026-10-06'));
  assert.throws(() => saveTaskArrangement(db, { ...input(db), day: '2026-10-02', scope: 'future', plan: interval(at(11, '2026-10-02'), at(12, '2026-10-02')) }, now), /过去/);
}));
test('recurrence mutations require explicit scope and reject unsupported or completed/skipped instances atomically', () => zone('UTC', () => {
  const db = fresh({ ...interval(), recurrence: 'FREQ=DAILY' }), before = JSON.stringify(db);
  assert.throws(() => saveTaskArrangement(db, { ...input(db), plan: interval(at(11), at(12)) }, now), /仅本次/);
  assert.throws(() => saveTaskArrangement(db, { ...input(db), scope: 'occurrence', plan: interval(at(11, '2026-10-04'), at(12, '2026-10-04')) }, now), /实例日期/);
  assert.equal(JSON.stringify(db), before);
  const unsupported = fresh({ ...interval(), recurrence: 'FREQ=WEEKLY;BYDAY=MO' });
  assert.throws(() => saveTaskArrangement(unsupported, { ...input(unsupported), plan: interval(at(11), at(12)), scope: 'occurrence' }, now), /原文/);
  assert.equal(parseImport(exportDatabase(unsupported)).database.tasks[0].recurrence, unsupported.tasks[0].recurrence);
}));
test('slot edits preserve other sessions, validate stale source/workspace, and undo cannot overwrite later time edits', () => zone('UTC', () => {
  const db = createWorkspace(fresh({ executionSlots: [slot(), slot(at(15), at(16))] }), 'Other'), ref = { source: 'executionSlot' as const, slotID: db.tasks[0].executionSlots[0].id };
  const next = saveTaskArrangement(db, { ...input(db), ref, plan: interval(at(10), at(11)), expected: interval() }, now);
  assert.deepEqual(next.tasks[0].executionSlots[1], db.tasks[0].executionSlots[1]);
  assert.throws(() => saveTaskArrangement(next, { ...input(db), ref, plan: interval(at(12), at(13)), expected: interval() }, now), /已更新/);
  assert.throws(() => saveTaskArrangement(db, { ...input(db), workspaceID: db.workspaces[1].id, ref, plan: interval() }, now), /another workspace/);
  const changed = setTaskDeadline(next, input(db).workspaceID, input(db).taskID, day, 'date'); assert.throws(() => undoTaskTimeChange(changed, db.tasks[0], next.tasks[0]), /后续修改/);
  const note = updateTask(next, input(db).taskID, { note: 'Keep this later note' }); const undo = undoTaskTimeChange(note, db.tasks[0], next.tasks[0]); assert.equal(undo.tasks[0].note, note.tasks[0].note); assert.deepEqual(timeState(undo.tasks[0]), timeState(db.tasks[0]));
}));
test('versioned exceptions survive save/reopen/import and invalid extension versions reject without repair', () => zone('UTC', () => {
  const db = fresh({ ...interval(), recurrence: 'FREQ=DAILY' });
  const next = saveTaskArrangement(db, { ...input(db), plan: interval(at(11), at(12)), scope: 'occurrence' }, now);
  const reopened = parseStoredDatabase(exportDatabase(next)).database; assert.deepEqual(reopened, JSON.parse(JSON.stringify(next))); assert.deepEqual(parseImport(exportDatabase(next)).database, JSON.parse(JSON.stringify(next)));
  assert.throws(() => validateDatabase({ ...next, tasks: [{ ...next.tasks[0], taskSchedule: { ...next.tasks[0].taskSchedule, version: 2 } }] }), /extension version/);
  assert.throws(() => validateDatabase({ ...next, tasks: [{ ...next.tasks[0], taskSchedule: { ...next.tasks[0].taskSchedule, exceptions: [{ day: '2026-02-30', plan: interval() }] } }] }), /civil day/);
  assert.equal(db.tasks[0].taskSchedule, undefined);
}));
test('cancel/draft construction is pure and edits never change actual records or active timers', () => zone('UTC', () => {
  const db = fresh({ ...interval() }); db.timeEntries = [{ id: crypto.randomUUID(), workspaceID: input(db).workspaceID, taskID: input(db).taskID, title: 'History', source: 'manual', startedAt: at(7), endedAt: at(8), note: 'Retain', activeSeconds: 1000 }];
  const before = JSON.stringify(db); resolvePlanDraft({ ...planDraft(db.tasks[0]), end: `${day}T11:00` }, db.tasks[0]); assert.equal(JSON.stringify(db), before);
  const next = saveTaskArrangement(db, { ...input(db), plan: interval(at(10), at(11)) }, now); assert.deepEqual(next.timeEntries, db.timeEntries); assert.equal(next.activeTimer, db.activeTimer);
}));
test('duration shortcuts retain exact elapsed time in a repeated DST hour', () => zone('America/New_York', () => {
  const original = { ...interval('2026-11-01T01:30:00-04:00'), plannedEnd: null };
  const draft = withPlanDuration(planDraft(original), original, 60), plan = resolvePlanDraft(draft, original);
  assert.equal(draft.end, '2026-11-01T01:30'); assert.equal(plan.plannedEnd, '2026-11-01T06:30:00.000Z');
  assert.equal(Date.parse(plan.plannedEnd!) - Date.parse(plan.plannedStart!), 3600000);
}));
test('daily reschedule status ignores independent sessions belonging to later occurrences', () => zone('UTC', () => {
  const db = fresh({ ...interval(), recurrence: 'FREQ=DAILY', executionSlots: [slot(at(13, '2026-10-04'), at(14, '2026-10-04'))] });
  assert.equal(needsReschedule(db.tasks[0], day, now), true);
}));
test('repeated cross-midnight adds remain idempotent and inconsistent new plans reject atomically', () => zone('UTC', () => {
  const db = fresh(), command = { ...input(db), start: at(23), end: at(1, '2026-10-04') };
  const next = addExecutionSlot(db, command, now); assert.strictEqual(addExecutionSlot(next, command, now), next);
  assert.throws(() => saveTaskArrangement(db, { ...input(db), plan: { ...interval(), plannedPrecision: 'none' } }, now), /精度/);
  assert.equal(db.tasks[0].plannedPrecision, 'none');
}));
test('daily enabling starts prospectively and stopping retains historical and explicit exception plans', () => zone('UTC', () => {
  const db = fresh({ ...interval(at(9, '2026-10-01'), at(10, '2026-10-01')) });
  const enabled = setDailyRecurrence(db, input(db).workspaceID, input(db).taskID, day, true, now);
  assert.equal(tasksForDay(enabled, input(db).workspaceID, '2026-10-02', now).length, 0);
  assert.equal(tasksForDay(enabled, input(db).workspaceID, '2026-10-04', now).length, 1);
  const exception = saveTaskArrangement(enabled, { ...input(db), day: '2026-10-05', scope: 'occurrence', plan: interval(at(15, '2026-10-05'), at(16, '2026-10-05')) }, now);
  const stopped = setDailyRecurrence(exception, input(db).workspaceID, input(db).taskID, '2026-10-04', false, now);
  assert.equal(planBlocksForDay(stopped.tasks[0], day).length, 1);
  assert.equal(tasksForDay(stopped, input(db).workspaceID, '2026-10-04', now).length, 0);
  assert.equal(planBlocksForDay(stopped.tasks[0], '2026-10-05')[0].start, new Date(at(15, '2026-10-05')).toISOString());
  assert.deepEqual(stopped.tasks[0].taskSchedule?.exceptions, exception.tasks[0].taskSchedule?.exceptions);
}));
test('timezone travel never corrupts or rejects scoped imported instants; ambiguous local day is warned', () => {
  const db = zone('Asia/Tokyo', () => {
    const source = fresh({ ...interval('2026-10-03T00:15:00+09:00', '2026-10-03T01:15:00+09:00'), recurrence: 'FREQ=DAILY' });
    return saveTaskArrangement(source, { ...input(source), plan: interval('2026-10-03T00:30:00+09:00', '2026-10-03T01:30:00+09:00'), scope: 'occurrence' }, new Date('2026-10-03T00:00:00+09:00'));
  });
  zone('America/Los_Angeles', () => {
    const imported = parseImport(exportDatabase(db)); assert.equal(imported.database.tasks[0].taskSchedule?.exceptions[0].plan.plannedStart, '2026-10-03T00:30:00+09:00');
    assert.ok(imported.warnings.some(warning => warning.includes('different local day'))); assert.ok(arrangementWarnings(imported.database.tasks[0], day).some(warning => warning.includes('时区')));
  });
});

test('general completion cannot create an occurrence before daily start or after stop', () => zone('UTC', () => {
  const db = fresh({ ...interval(at(9, '2026-10-01'), at(10, '2026-10-01')) });
  const notStarted = setDailyRecurrence(db, input(db).workspaceID, input(db).taskID, '2026-10-05', true, now);
  assert.throws(() => completeTask(notStarted, input(db).taskID, day, now), /没有可完成/);
  const started = setDailyRecurrence(db, input(db).workspaceID, input(db).taskID, day, true, now);
  const stopped = setDailyRecurrence(started, input(db).workspaceID, input(db).taskID, day, false, now);
  assert.throws(() => completeTask(stopped, input(db).taskID, day, now), /没有可完成/);
  const explicit = addExecutionSlot(stopped, { ...input(db), start: at(9), end: at(10) }, now);
  const done = completeTask(explicit, input(db).taskID, day, now); assert.ok(done.tasks[0].completedInstances.includes(day)); assert.strictEqual(completeTask(done, input(db).taskID, day, now), done);
}));

test('scoped schedule survives the real atomic store and retains the previous valid backup', async () => {
  const { mkdtemp, readFile, rm } = await import('node:fs/promises');
  const { tmpdir } = await import('node:os'); const { join } = await import('node:path');
  const { PlannerStore } = await import('../electron/store.js');
  const directory = await mkdtemp(join(tmpdir(), 'gtd-time-convergence-'));
  try {
    const db = fresh({ ...interval(), recurrence: 'FREQ=DAILY' });
    const store = new PlannerStore(directory); await store.save(db);
    const next = saveTaskArrangement(db, { ...input(db), plan: interval(at(11), at(12)), scope: 'occurrence' }, now);
    await store.save(next); const reopened = (await new PlannerStore(directory).load()).database!;
    assert.deepEqual(reopened.tasks[0].taskSchedule, next.tasks[0].taskSchedule);
    assert.equal(parseStoredDatabase(await readFile(store.file + '.bak', 'utf8')).database.tasks[0].taskSchedule, undefined);
    assert.deepEqual(reopened.timeEntries, db.timeEntries);
  } finally { await rm(directory, { recursive: true, force: true }); }
});

test('legacy date-precision ISO mixed with a civil end survives timezone travel in scoped schedules', () => {
  const db = zone('Asia/Tokyo', () => {
    const source = fresh({ plannedStart: '2026-10-03T00:00:00+09:00', plannedEnd: null, plannedPrecision: 'date', recurrence: 'FREQ=DAILY' });
    const plan = resolvePlanDraft({ ...planDraft(source.tasks[0]), end: day }, source.tasks[0]);
    return saveTaskArrangement(source, { ...input(source), plan, scope: 'occurrence' }, new Date('2026-10-03T00:00:00+09:00'));
  });
  for (const tz of ['America/Los_Angeles', 'Pacific/Kiritimati']) zone(tz, () => {
    const imported = parseImport(exportDatabase(db)); assert.equal(imported.database.tasks[0].taskSchedule?.exceptions[0].plan.plannedStart, '2026-10-03T00:00:00+09:00');
    assert.equal(imported.database.tasks[0].taskSchedule?.exceptions[0].plan.plannedEnd, day);
  });
});
