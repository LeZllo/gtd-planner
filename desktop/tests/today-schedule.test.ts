import test from 'node:test';
import assert from 'node:assert/strict';
import { actualFocusForDay, addExecutionSlot, addTimeEntry, canScheduleTaskOnDay, completeTask, createTask, createWorkspace, dayBounds, deadlineInstant, deleteTimeEntry, emptyDatabase, exportDatabase, hasTimeEntryConflict, makeScheduleSelection, normalizePomodoroMinutes, parseStoredDatabase, pauseTimer, planConflicts, pomodoroClockState, removeExecutionSlot, setTaskCompletionForDay, startTimer, startTimerSession, stopTimer, tasksForDay, timerSeconds, todayScheduleSnapshot, updateTimeEntry, validateDatabase, wallClockTime, type GTDDatabase, type GTDTask, type TimeEntry } from '../src/domain/index.js';

const now = new Date('2026-04-12T12:00:00Z');
const iso = (hour: number, day = 12, minute = 0) => new Date(Date.UTC(2026, 3, day, hour, minute)).toISOString();
function fresh(count = 1): GTDDatabase { let db = emptyDatabase(); for (let i = 0; i < count; i++) db = createTask(db, { workspaceID: db.workspaces[0].id, title: `Task ${i}` }); return db; }
function task(db: GTDDatabase, patch: Partial<GTDTask>, index = 0): GTDDatabase { return { ...db, tasks: db.tasks.map((t, i) => i === index ? { ...t, ...patch } : t) }; }
const wid = (db: GTDDatabase) => db.workspaces[0].id;
const tid = (db: GTDDatabase, index = 0) => db.tasks[index].id;
const slot = (start: string, end: string) => ({ id: crypto.randomUUID(), start, end });
const encoded = (db: GTDDatabase) => JSON.stringify(db);
function zone<T>(tz: string, run: () => T): T { const previous = process.env.TZ; process.env.TZ = tz; try { return run(); } finally { if (previous === undefined) delete process.env.TZ; else process.env.TZ = previous; } }
function record(db: GTDDatabase, patch: Partial<TimeEntry> = {}): TimeEntry { return { id: crypto.randomUUID(), workspaceID: wid(db), title: 'Actual', startedAt: iso(9), endedAt: iso(10), source: 'manual', note: '', ...patch }; }

// All timezone changes below are synchronous and isolated; node runs each
// test file in its own process, so existing parallel suites remain unaffected.
test('snapshot clips slots at midnight, preserves point plans with zero duration, and excludes undated inbox', () => zone('UTC', () => {
  let db = fresh(4);
  db = task(db, { executionSlots: [slot(iso(23, 11), iso(1))] });
  db = task(db, { plannedStart: iso(10), plannedPrecision: 'minute' }, 1);
  db = task(db, { plannedStart: iso(23), plannedEnd: iso(0, 13), plannedPrecision: 'minute' }, 2);
  const before = encoded(db), snapshot = todayScheduleSnapshot(db, wid(db), '2026-04-12', now);
  assert.equal(snapshot.tasks.length, 3); assert.equal(snapshot.planBlocks.length, 3);
  assert.equal(snapshot.planBlocks[0].start, iso(0)); assert.equal(snapshot.planBlocks[0].plannedDuration, 3600);
  const point = snapshot.planBlocks.find(b => b.taskID === tid(db, 1))!;
  assert.equal(point.isPoint, true); assert.equal(point.plannedDuration, 0); assert.equal(point.end, iso(10, 12, 30));
  assert.equal(snapshot.plannedDuration, 7200); assert.equal(snapshot.waitingCount, 0);
  assert.equal(todayScheduleSnapshot(db, wid(db), '2026-04-13', now).planBlocks.length, 0); assert.equal(encoded(db), before);
}));

test('multi-day plans stay in progress or complete-within drawer until explicitly scheduled', () => zone('UTC', () => {
  let db = fresh(3);
  db = task(db, { plannedStart: '2026-04-10', plannedEnd: '2026-04-13', plannedPrecision: 'date', planRangeIntent: 'progress' });
  db = task(db, { plannedStart: iso(9, 11), plannedEnd: iso(12, 13), plannedPrecision: 'minute', planRangeIntent: 'complete-within' }, 1);
  db = task(db, { deadline: '2026-04-12', deadlinePrecision: 'date' }, 2);
  let snapshot = todayScheduleSnapshot(db, wid(db), '2026-04-12', now);
  assert.equal(snapshot.crossDayProgressTasks[0].id, tid(db)); assert.equal(snapshot.completeWithinTasks[0].id, tid(db, 1));
  assert.equal(snapshot.planBlocks.length, 0); assert.equal(snapshot.waitingCount, 3); assert.equal(snapshot.deadlineTasks.length, 1);
  db = addExecutionSlot(db, { workspaceID: wid(db), taskID: tid(db), start: iso(9), end: iso(10) }, now);
  snapshot = todayScheduleSnapshot(db, wid(db), '2026-04-12', now);
  assert.equal(snapshot.waitingCount, 2); assert.equal(snapshot.crossDayProgressTasks.length, 1);
}));

test('daily completed instances remain visible; skipped and pre-anchor days disappear', () => zone('UTC', () => {
  const db = task(fresh(), { recurrence: 'FREQ=DAILY', plannedStart: iso(9, 10), plannedEnd: iso(10, 10), plannedPrecision: 'minute', completedInstances: ['2026-04-11'], skippedInstances: ['2026-04-12'] });
  const done = todayScheduleSnapshot(db, wid(db), '2026-04-11', now);
  assert.equal(done.completedCount, 1); assert.equal(done.remainingCount, 0); assert.equal(done.drawerTasks.length, 0);
  assert.equal(done.planBlocks[0].start, iso(9, 11));
  assert.equal(todayScheduleSnapshot(db, wid(db), '2026-04-09', now).tasks.length, 0);
  assert.equal(todayScheduleSnapshot(db, wid(db), '2026-04-12', now).tasks.length, 0);
  assert.equal(todayScheduleSnapshot(db, wid(db), '2026-04-13', now).planBlocks[0].start, iso(9, 13));
}));

test('DAILY variants outside supported plain rules stay preserved and are not expanded', () => zone('UTC', () => {
  const db = task(fresh(), { recurrence: 'FREQ=DAILY;INTERVAL=2', plannedStart: iso(9), plannedEnd: iso(10), plannedPrecision: 'minute' });
  assert.equal(todayScheduleSnapshot(db, wid(db), '2026-04-13', now).tasks.length, 0);
  assert.equal(db.tasks[0].recurrence, 'FREQ=DAILY;INTERVAL=2');
}));

test('daily templates preserve wall time through DST gaps and recover inverted normalized ranges', () => zone('America/New_York', () => {
  let db = task(fresh(), { recurrence: 'FREQ=DAILY', plannedPrecision: 'minute', plannedStart: '2026-03-07T02:30:00-05:00', plannedEnd: '2026-03-07T03:00:00-05:00' });
  const before = encoded(db), snapshot = todayScheduleSnapshot(db, wid(db), '2026-03-08', new Date('2026-03-08T16:00:00Z'));
  assert.equal(snapshot.planBlocks[0].start, '2026-03-08T07:30:00.000Z'); assert.equal(snapshot.planBlocks[0].end, '2026-03-08T08:00:00.000Z');
  assert.equal(snapshot.plannedDuration, 1800); assert.equal(Date.parse(snapshot.dayEnd) - Date.parse(snapshot.dayStart), 23 * 3600_000);
  assert.equal(encoded(db), before);
  db = task(db, { plannedStart: '2026-03-07T09:00:00-05:00', plannedEnd: '2026-03-07T10:00:00-05:00' });
  assert.equal(todayScheduleSnapshot(db, wid(db), '2026-03-08').planBlocks[0].start, '2026-03-08T13:00:00.000Z');
}));

test('daily templates select first repeated fall-back time and use the 25-hour day boundary', () => zone('America/New_York', () => {
  const db = task(fresh(), { recurrence: 'RRULE:FREQ=DAILY;INTERVAL=1', plannedPrecision: 'minute', plannedStart: '2026-10-31T01:30:00-04:00', plannedEnd: '2026-10-31T02:30:00-04:00' });
  const snapshot = todayScheduleSnapshot(db, wid(db), '2026-11-01', new Date('2026-11-01T18:00:00Z'));
  assert.equal(snapshot.planBlocks[0].start, '2026-11-01T05:30:00.000Z'); assert.equal(snapshot.planBlocks[0].end, '2026-11-01T07:30:00.000Z');
  assert.equal(snapshot.plannedDuration, 7200); assert.equal(Date.parse(snapshot.dayEnd) - Date.parse(snapshot.dayStart), 25 * 3600_000);
}));

test('exact deadline crossing reclassifies without changing data; backlog only joins actual Today', () => zone('UTC', () => {
  let db = fresh(3); db = task(db, { deadline: iso(12), deadlinePrecision: 'minute' });
  db = task(db, { deadline: iso(12, 11), deadlinePrecision: 'minute' }, 1);
  db = task(db, { deadline: '2026-04-12', deadlinePrecision: 'date' }, 2);
  const before = encoded(db);
  assert.equal(todayScheduleSnapshot(db, wid(db), '2026-04-12', now).overdueCount, 1);
  assert.equal(todayScheduleSnapshot(db, wid(db), '2026-04-12', new Date(+now + 1)).overdueCount, 2);
  assert.equal(deadlineInstant(db.tasks[2]), Date.parse(iso(0, 13)));
  assert.equal(tasksForDay(db, wid(db), '2026-04-13', now).length, 0);
  assert.equal(tasksForDay(db, wid(db), '2026-04-13', new Date(iso(12, 13))).length, 3);
  assert.equal(encoded(db), before);
}));

test('date-only deadline and daily anchor semantics use local civil day in both hemispheres', () => {
  for (const tz of ['America/Los_Angeles', 'Asia/Tokyo']) zone(tz, () => {
    const db = task(fresh(), { deadline: '2026-04-12', deadlinePrecision: 'date' });
    assert.equal(deadlineInstant(db.tasks[0]), dayBounds('2026-04-12')[1]);
    const localNoon = new Date(2026, 3, 12, 12); assert.equal(todayScheduleSnapshot(db, wid(db), '2026-04-12', localNoon).overdueCount, 0);
  });
});

test('snap previews are pure, reversible, clamped to 00–24, and use Alt 5-minute increments', () => zone('UTC', () => {
  assert.deepEqual(makeScheduleSelection('2026-04-12', 611, 580), { start: iso(9, 12, 45), end: iso(10, 12, 15), startMinute: 585, endMinute: 615 });
  assert.deepEqual(makeScheduleSelection('2026-04-12', 611, 580, true), { start: iso(9, 12, 40), end: iso(10, 12, 10), startMinute: 580, endMinute: 610 });
  const end = makeScheduleSelection('2026-04-12', 2000, 2000); assert.equal(end.start, iso(23, 12, 45)); assert.equal(end.end, iso(0, 13));
  assert.equal(makeScheduleSelection('2026-04-12', -100, -5).end, iso(0, 12, 15));
  assert.throws(() => makeScheduleSelection('2026-04-12', NaN, 50), /finite/);
  assert.throws(() => makeScheduleSelection('2026-02-30', 0, 20), /valid/);
}));

test('snap gap/fold selections stay positive inside the correct local day', () => zone('America/New_York', () => {
  const gap = makeScheduleSelection('2026-03-08', 150, 180); assert.equal(gap.start, '2026-03-08T07:30:00.000Z'); assert.equal(gap.end, '2026-03-08T08:00:00.000Z');
  const fold = makeScheduleSelection('2026-11-01', 90, 120); assert.equal(fold.start, '2026-11-01T05:30:00.000Z'); assert.equal(fold.end, '2026-11-01T07:00:00.000Z');
  for (const day of ['2026-03-08', '2026-11-01']) { const s = makeScheduleSelection(day, 1440, 1440); assert.equal(Date.parse(s.end), dayBounds(day)[1]); assert.ok(Date.parse(s.end) > Date.parse(s.start)); }
  assert.equal(wallClockTime('2026-03-08', 150).getHours(), 3);
}));

test('point-plan conflicts use the instant, never its cosmetic half-hour footprint; ordinary overlaps only warn', () => zone('UTC', () => {
  let db = task(fresh(2), { plannedStart: iso(9), plannedPrecision: 'minute' });
  let snapshot = todayScheduleSnapshot(db, wid(db), '2026-04-12', now);
  assert.equal(planConflicts({ start: iso(9, 12, 10), end: iso(9, 12, 20) }, snapshot.planBlocks), false);
  assert.equal(planConflicts({ start: iso(9), end: iso(9, 12, 15) }, snapshot.planBlocks), true);
  db = addExecutionSlot(db, { workspaceID: wid(db), taskID: tid(db, 1), start: iso(9), end: iso(10) }, now);
  snapshot = todayScheduleSnapshot(db, wid(db), '2026-04-12', now); assert.equal(snapshot.planBlocks.length, 2);
  assert.equal(planConflicts({ start: iso(10), end: iso(11) }, snapshot.planBlocks), false);
}));

test('planning commands validate workspace and finished status, deduplicate instants, and remove idempotently', () => zone('UTC', () => {
  let db = createWorkspace(fresh(), 'Other'); const input = { workspaceID: wid(db), taskID: tid(db), start: iso(9), end: iso(10) };
  const before = encoded(db); assert.throws(() => addExecutionSlot(db, { ...input, workspaceID: db.workspaces[1].id }), /another workspace/);
  assert.throws(() => addExecutionSlot(task(db, { status: 'done' }), input), /Finished/); assert.throws(() => addExecutionSlot(db, { ...input, end: input.start }), /after/);
  assert.equal(encoded(db), before);
  db = addExecutionSlot(db, input, now); const saved = db;
  assert.strictEqual(addExecutionSlot(db, { ...input, start: '2026-04-12T11:00:00+02:00', end: '2026-04-12T12:00:00+02:00' }, now), saved);
  assert.throws(() => removeExecutionSlot(db, db.workspaces[1].id, tid(db), db.tasks[0].executionSlots[0].id), /another workspace/);
  const slotID = db.tasks[0].executionSlots[0].id; db = removeExecutionSlot(db, wid(db), tid(db), slotID); assert.equal(db.tasks[0].executionSlots.length, 0);
  assert.strictEqual(removeExecutionSlot(db, wid(db), tid(db), slotID), db);
}));

test('daily scheduling validates every occupied day but not an exclusive midnight endpoint', () => zone('UTC', () => {
  const db = task(fresh(), { recurrence: 'FREQ=DAILY', plannedStart: '2026-04-10', plannedPrecision: 'date', completedInstances: ['2026-04-11'], skippedInstances: ['2026-04-13'] });
  const add = (start: string, end: string) => addExecutionSlot(db, { workspaceID: wid(db), taskID: tid(db), start, end }, now);
  assert.throws(() => add(iso(23, 9), iso(1, 10)), /before/); assert.throws(() => add(iso(23, 10), iso(1, 11)), /completed/);
  assert.throws(() => add(iso(23), iso(1, 13)), /skipped/);
  assert.equal(add(iso(23), iso(0, 13)).tasks[0].executionSlots.length, 1);
  assert.equal(canScheduleTaskOnDay(db.tasks[0], '2026-04-11'), false); assert.equal(db.tasks[0].executionSlots.length, 0);
}));

test('actual projection keeps original editable bounds, prorates saved active seconds, and shares report totals', () => zone('UTC', () => {
  let db = fresh(); const entry = record(db, { startedAt: iso(23, 11), endedAt: iso(1), source: 'stopwatch', activeSeconds: 1200, custom: { retained: true } });
  db = { ...db, timeEntries: [entry] }; const before = encoded(db);
  const snapshot = todayScheduleSnapshot(db, wid(db), '2026-04-12', now);
  assert.strictEqual(snapshot.actualEntries[0], entry); assert.strictEqual(snapshot.actualBlocks[0].entry, entry);
  assert.equal(snapshot.actualBlocks[0].start, iso(0)); assert.equal(snapshot.actualBlocks[0].actualDuration, 600); assert.equal(snapshot.actualEstimated, true);
  assert.deepEqual({ seconds: snapshot.actualDuration, estimated: snapshot.actualEstimated }, actualFocusForDay(db.timeEntries, wid(db), '2026-04-12'));
  assert.equal(snapshot.actualDuration + todayScheduleSnapshot(db, wid(db), '2026-04-11', now).actualDuration, 1200);
  assert.equal(encoded(db), before);
}));

test('manual actual add preserves plans, supports finished-task history and no-task entries, and rejects future or invalid workspace', () => zone('UTC', () => {
  let db = task(createWorkspace(fresh(), 'Other'), { plannedStart: iso(10), plannedEnd: iso(11), plannedPrecision: 'minute', deadline: iso(12), deadlinePrecision: 'minute', status: 'done' });
  const plans = encoded(db), input = { workspaceID: wid(db), taskID: tid(db), startedAt: iso(9), endedAt: iso(10), note: 'Review' };
  assert.throws(() => addTimeEntry(db, { ...input, workspaceID: db.workspaces[1].id }, now), /another workspace/);
  assert.throws(() => addTimeEntry(db, { ...input, endedAt: iso(13) }, now), /future/);
  assert.throws(() => addTimeEntry(db, { ...input, endedAt: iso(9) }, now), /after/); assert.equal(encoded(db), plans);
  const saved = addTimeEntry(db, input, now); assert.strictEqual(saved.tasks, db.tasks); assert.equal(saved.timeEntries[0].activeSeconds, 3600); assert.equal(saved.timeEntries[0].source, 'manual');
  db = addTimeEntry(saved, { workspaceID: wid(db), startedAt: iso(10), endedAt: iso(11) }, now);
  assert.equal(db.timeEntries[1].taskID, null); assert.equal(db.timeEntries[1].title, '无任务专注'); assert.equal(db.schemaVersion, 11);
}));

test('actual ranges hard-reject intersections but allow adjacent records, distinct workspaces, and reject duplicate submissions', () => zone('UTC', () => {
  let db = createWorkspace(fresh(), 'Other'); const input = { workspaceID: wid(db), startedAt: iso(9), endedAt: iso(10) };
  db = addTimeEntry(db, input, now); const before = encoded(db);
  assert.throws(() => addTimeEntry(db, input, now), /overlap/); assert.throws(() => addTimeEntry(db, { ...input, startedAt: iso(8), endedAt: iso(9, 12, 1) }, now), /overlap/);
  assert.equal(encoded(db), before); assert.equal(hasTimeEntryConflict(db, wid(db), iso(10), iso(11), undefined, now), false);
  db = addTimeEntry(db, { ...input, workspaceID: db.workspaces[1].id }, now); assert.equal(db.timeEntries.length, 2);
}));

test('manual actual conflicts include running and paused timers in the selected workspace', () => zone('UTC', () => {
  let db = createWorkspace(fresh(), 'Other'); db = startTimerSession(db, { workspaceID: wid(db), mode: 'stopwatch' }, new Date(iso(9)));
  const input = { workspaceID: wid(db), startedAt: iso(10), endedAt: iso(11) };
  assert.throws(() => addTimeEntry(db, input, now), /active timer/);
  const other = addTimeEntry(db, { ...input, workspaceID: db.workspaces[1].id }, now); assert.equal(other.timeEntries.length, 1);
  db = pauseTimer(db, new Date(iso(10))); assert.throws(() => addTimeEntry(db, { ...input, startedAt: iso(9, 12, 30) }, now), /overlap/);
  assert.equal(addTimeEntry(db, input, now).timeEntries.length, 1); assert.equal(db.timeEntries.length, 0);
}));

test('actual metadata edits preserve paused active seconds, source, plan identity and unknown fields; range edits reset duration', () => zone('UTC', () => {
  let db = fresh(); const entry = record(db, { taskID: tid(db), source: 'pomodoro', pomodoroPhase: 'focus', activeSeconds: 120, extension: { keep: [1, 2] } });
  db = { ...db, timeEntries: [entry], customDatabase: ['preserve'] }; const taskBefore = db.tasks;
  db = updateTimeEntry(db, wid(db), entry.id, { note: 'New note' }, now);
  assert.equal(db.timeEntries[0].activeSeconds, 120); assert.equal(db.timeEntries[0].source, 'pomodoro'); assert.equal(db.timeEntries[0].pomodoroPhase, 'focus');
  assert.deepEqual(db.timeEntries[0].extension, { keep: [1, 2] }); assert.strictEqual(db.tasks, taskBefore);
  assert.strictEqual(updateTimeEntry(db, wid(db), entry.id, { note: 'New note' }, now), db);
  db = updateTimeEntry(db, wid(db), entry.id, { startedAt: '2026-04-12T11:00:00+02:00' }, now); assert.equal(db.timeEntries[0].activeSeconds, 120);
  db = updateTimeEntry(db, wid(db), entry.id, { endedAt: iso(11) }, now); assert.equal(db.timeEntries[0].activeSeconds, 7200);
  assert.deepEqual(db.customDatabase, ['preserve']); assert.equal(db.schemaVersion, 11);
}));

test('actual edit guards are atomic; metadata-only imported future entries remain editable', () => zone('UTC', () => {
  let db = createWorkspace(fresh(), 'Other'); db = { ...db, timeEntries: [record(db), record(db, { startedAt: iso(10), endedAt: iso(11) })] };
  const id = db.timeEntries[0].id, before = encoded(db);
  assert.throws(() => updateTimeEntry(db, wid(db), id, { endedAt: iso(10, 12, 1) }, now), /overlap/);
  assert.throws(() => updateTimeEntry(db, db.workspaces[1].id, id, { note: 'wrong' }, now), /another workspace/);
  assert.throws(() => updateTimeEntry(db, wid(db), id, { source: 'manual' } as never, now), /Only/);
  assert.throws(() => updateTimeEntry(db, wid(db), id, { endedAt: iso(13) }, now), /future/); assert.equal(encoded(db), before);
  const future = record(db, { startedAt: iso(9, 13), endedAt: iso(10, 13), activeSeconds: 200 }); db = { ...db, timeEntries: [future] };
  db = updateTimeEntry(db, wid(db), future.id, { note: 'Imported timestamp kept' }, now); assert.equal(db.timeEntries[0].activeSeconds, 200);
  assert.throws(() => updateTimeEntry(db, wid(db), future.id, { endedAt: iso(11, 13) }, now), /future/);
}));

test('actual record reassociation resolves canonical task and does not move records across workspaces', () => zone('UTC', () => {
  let db = fresh(2); db = createWorkspace(db, 'Other'); db = createTask(db, { workspaceID: db.workspaces[1].id, title: 'Other task' });
  db = { ...db, timeEntries: [record(db)] }; const entryID = db.timeEntries[0].id;
  db = updateTimeEntry(db, wid(db), entryID, { taskID: tid(db, 1).toUpperCase() }, now); assert.equal(db.timeEntries[0].taskID, tid(db, 1)); assert.equal(db.timeEntries[0].title, db.tasks[1].title);
  assert.throws(() => updateTimeEntry(db, wid(db), entryID, { taskID: tid(db, 2) }, now), /another workspace/);
  db = updateTimeEntry(db, wid(db), entryID, { taskID: null }, now); assert.equal(db.timeEntries[0].title, '无任务专注');
}));

test('actual delete is idempotent, workspace scoped, and never deletes the active timer or plans', () => zone('UTC', () => {
  let db = createWorkspace(fresh(), 'Other'); db = { ...db, timeEntries: [record(db, { endedAt: iso(9, 12, 30) })] };
  db = startTimerSession(db, { workspaceID: wid(db), taskID: tid(db), mode: 'stopwatch' }, new Date(iso(10)));
  const id = db.timeEntries[0].id, timer = db.activeTimer, tasks = db.tasks;
  assert.throws(() => deleteTimeEntry(db, db.workspaces[1].id, id), /another workspace/);
  db = deleteTimeEntry(db, wid(db), id); assert.equal(db.timeEntries.length, 0); assert.strictEqual(db.activeTimer, timer); assert.strictEqual(db.tasks, tasks);
  assert.strictEqual(deleteTimeEntry(db, wid(db), id), db);
}));

test('optional-task timer targets normalize 1–180 minutes, retain overtime, and old call remains compatible', () => zone('UTC', () => {
  let db = fresh(); const original = db;
  db = startTimerSession(db, { workspaceID: wid(db), mode: 'pomodoro', targetMinutes: 42.6 }, now);
  assert.equal(db.activeTimer!.targetSeconds, 43 * 60); assert.equal(db.activeTimer!.taskID, null);
  assert.equal(timerSeconds(db.activeTimer!, new Date(+now + 44 * 60_000)), 44 * 60); assert.equal(db.timeEntries.length, 0);
  assert.deepEqual(pomodoroClockState(43 * 60, 44 * 60), { phase: 'overtime', seconds: 60 }); assert.deepEqual(pomodoroClockState(60, 60), { phase: 'overtime', seconds: 0 });
  db = stopTimer(db, new Date(+now + 44 * 60_000)); assert.equal(db.timeEntries[0].activeSeconds, 44 * 60); assert.equal(db.timeEntries[0].taskID, null);
  assert.equal(normalizePomodoroMinutes(-2), 1); assert.equal(normalizePomodoroMinutes(181), 180); assert.throws(() => normalizePomodoroMinutes(Infinity), /finite/);
  assert.equal(startTimer(original, tid(original), 'pomodoro', now).activeTimer!.targetSeconds, 1500);
  assert.deepEqual(parseStoredDatabase(exportDatabase(db)).database.timeEntries, db.timeEntries);
}));

test('timer starts reject wrong workspace, finished tasks and concurrent starts without altering state', () => zone('UTC', () => {
  let db = createWorkspace(fresh(), 'Other'); const before = encoded(db);
  assert.throws(() => startTimerSession(db, { workspaceID: db.workspaces[1].id, taskID: tid(db), mode: 'pomodoro' }, now), /another workspace/);
  assert.throws(() => startTimerSession(task(db, { status: 'done' }), { workspaceID: wid(db), taskID: tid(db), mode: 'pomodoro' }, now), /Reopen/); assert.equal(encoded(db), before);
  db = startTimerSession(db, { workspaceID: wid(db), mode: 'stopwatch' }, now); const active = encoded(db);
  assert.throws(() => startTimerSession(db, { workspaceID: wid(db), mode: 'pomodoro' }, now), /current timer/); assert.equal(encoded(db), active);
}));

test('dated completion is explicit/idempotent, keeps daily series, and rejects future/historical ordinary changes', () => zone('UTC', () => {
  let db = task(createWorkspace(fresh(), 'Other'), { recurrence: 'FREQ=DAILY', plannedStart: '2026-04-10', plannedPrecision: 'date', skippedInstances: ['2026-04-11'] });
  const before = encoded(db);
  assert.throws(() => setTaskCompletionForDay(db, wid(db), tid(db), '2026-04-13', true, now), /today/);
  assert.throws(() => setTaskCompletionForDay(db, wid(db), tid(db), '2026-04-09', true, now), /before/);
  assert.throws(() => setTaskCompletionForDay(db, wid(db), tid(db), '2026-04-11', true, now), /skipped/);
  assert.throws(() => setTaskCompletionForDay(db, db.workspaces[1].id, tid(db), '2026-04-12', true, now), /another workspace/); assert.equal(encoded(db), before);
  db = setTaskCompletionForDay(db, wid(db), tid(db), '2026-04-12', true, now); assert.equal(db.tasks[0].status, 'inbox');
  assert.strictEqual(setTaskCompletionForDay(db, wid(db), tid(db), '2026-04-12', true, now), db);
  db = setTaskCompletionForDay(db, wid(db), tid(db), '2026-04-12', false, now); assert.equal(db.tasks[0].completedInstances.length, 0);
  assert.strictEqual(setTaskCompletionForDay(db, wid(db), tid(db), '2026-04-12', false, now), db);
  db = task(db, { recurrence: '' }); assert.throws(() => setTaskCompletionForDay(db, wid(db), tid(db), '2026-04-10', true, now), /Historical/);
  db = completeTask(db, tid(db), '2026-04-12', now); assert.equal(db.tasks[0].completedAt, now.toISOString());
  db = setTaskCompletionForDay(db, wid(db), tid(db), '2026-04-12', false, now); assert.equal(db.tasks[0].status, 'open'); validateDatabase(db);
}));

test('metadata and equivalent-instant edits retain fractional/offset raw text and untouched object identity', () => zone('UTC', () => {
  let db = fresh(); const original = record(db, { startedAt: '2026-04-12T11:00:00.123456789+02:00', endedAt: '2026-04-12T12:00:00.123456789+02:00', source: 'stopwatch', activeSeconds: 80, extra: { raw: 'retained' } });
  const unrelated = record(db, { startedAt: iso(10, 12, 30), endedAt: iso(11) }); db = { ...db, timeEntries: [original, unrelated] };
  assert.strictEqual(updateTimeEntry(db, wid(db), original.id, { startedAt: '2026-04-12T09:00:00.123Z', endedAt: '2026-04-12T10:00:00.123Z' }, now), db);
  const updated = updateTimeEntry(db, wid(db), original.id, { note: 'Metadata only' }, now);
  assert.equal(updated.timeEntries[0].startedAt, original.startedAt); assert.equal(updated.timeEntries[0].endedAt, original.endedAt);
  assert.equal(updated.timeEntries[0].activeSeconds, 80); assert.strictEqual(updated.timeEntries[0].extra, original.extra);
  assert.strictEqual(updated.timeEntries[1], unrelated); assert.strictEqual(updated.tasks, db.tasks); assert.equal(original.note, '');
}));

test('dated completion requires current day membership while general task completion still accepts undated work', () => zone('UTC', () => {
  const db = fresh(), before = encoded(db);
  for (const completed of [true, false]) assert.throws(() => setTaskCompletionForDay(db, wid(db), tid(db), '2026-04-12', completed, now), /belongs to the selected day/);
  assert.equal(encoded(db), before);
  const general = completeTask(db, tid(db), undefined, now); assert.equal(general.tasks[0].status, 'done');
  const due = task(db, { deadline: iso(10, 11), deadlinePrecision: 'minute' });
  const completed = setTaskCompletionForDay(due, wid(due), tid(due), '2026-04-12', true, now);
  assert.equal(completed.tasks[0].completedAt, now.toISOString());
  assert.strictEqual(setTaskCompletionForDay(completed, wid(completed), tid(completed), '2026-04-12', true, now), completed);
  assert.equal(setTaskCompletionForDay(completed, wid(completed), tid(completed), '2026-04-12', false, now).tasks[0].status, 'open');
}));

test('dated completion rejects stale rows after the current plan or slot moves away', () => zone('UTC', () => {
  const planned = task(fresh(), { plannedStart: iso(9), plannedEnd: iso(10), plannedPrecision: 'minute' });
  assert.equal(todayScheduleSnapshot(planned, wid(planned), '2026-04-12', now).tasks.length, 1);
  const moved = task(planned, { plannedStart: iso(9, 13), plannedEnd: iso(10, 13) });
  const removed = task(planned, { plannedStart: null, plannedEnd: null, plannedPrecision: 'none' });
  for (const current of [moved, removed]) {
    const before = encoded(current);
    assert.throws(() => setTaskCompletionForDay(current, wid(current), tid(current), '2026-04-12', true, now), /belongs to the selected day/);
    assert.equal(encoded(current), before);
  }
  let slotted = task(removed, { executionSlots: [slot(iso(9), iso(10))] });
  assert.equal(todayScheduleSnapshot(slotted, wid(slotted), '2026-04-12', now).tasks.length, 1);
  slotted = removeExecutionSlot(slotted, wid(slotted), tid(slotted), slotted.tasks[0].executionSlots[0].id);
  assert.throws(() => setTaskCompletionForDay(slotted, wid(slotted), tid(slotted), '2026-04-12', true, now), /belongs to the selected day/);
}));

test('dated reopen requires completion on this day and cannot reopen an older completion through today', () => zone('UTC', () => {
  let db = task(fresh(), { status: 'done', completedAt: iso(10, 11), plannedStart: iso(9), plannedEnd: iso(10), plannedPrecision: 'minute' });
  const before = encoded(db);
  assert.throws(() => setTaskCompletionForDay(db, wid(db), tid(db), '2026-04-12', false, now), /belongs to the selected day/);
  assert.throws(() => setTaskCompletionForDay(db, wid(db), tid(db), '2026-04-11', false, now), /Historical/); assert.equal(encoded(db), before);
  db = task(db, { completedAt: iso(10) });
  assert.equal(setTaskCompletionForDay(db, wid(db), tid(db), '2026-04-12', false, now).tasks[0].status, 'open');
}));

test('midnight commit revalidation rejects an ordinary yesterday row but retains historical daily occurrences', () => zone('America/New_York', () => {
  const day = '2026-03-07', beforeMidnight = new Date('2026-03-08T04:59:59.999Z'), midnight = new Date('2026-03-08T05:00:00Z');
  const db = task(fresh(), { plannedStart: '2026-03-07T10:00:00-05:00', plannedPrecision: 'minute' });
  assert.equal(todayScheduleSnapshot(db, wid(db), day, beforeMidnight).tasks.length, 1);
  assert.equal(setTaskCompletionForDay(db, wid(db), tid(db), day, true, beforeMidnight).tasks[0].status, 'done');
  const before = encoded(db); assert.throws(() => setTaskCompletionForDay(db, wid(db), tid(db), day, true, midnight), /Historical/); assert.equal(encoded(db), before);
  let daily = task(db, { recurrence: 'FREQ=DAILY' });
  daily = setTaskCompletionForDay(daily, wid(daily), tid(daily), day, true, midnight); assert.deepEqual(daily.tasks[0].completedInstances, [day]);
  daily = setTaskCompletionForDay(daily, wid(daily), tid(daily), day, false, midnight); assert.deepEqual(daily.tasks[0].completedInstances, []);
  const skipped = task(daily, { skippedInstances: [day] });
  assert.throws(() => setTaskCompletionForDay(skipped, wid(skipped), tid(skipped), day, false, midnight), /skipped/);
}));
