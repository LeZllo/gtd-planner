import test from 'node:test';
import assert from 'node:assert/strict';
import { completeTask, createProject, createTask, createWorkspace, dayKey, demoDatabase, duplicateTask, emptyDatabase, exportDatabase, moveTask, parseImport, parseStoredDatabase, pauseTimer, restoreTrash, resumeTimer, startTimer, stopTimer, taskTree, tasksForDay, timerSeconds, trashTask, updateTask, validateDatabase, type GTDDatabase, type GTDTask } from '../src/domain/index.js';

const now = new Date('2026-04-12T10:00:00.000Z');
const uuid = (n: number) => `aaaaaaaa-0000-4000-8000-${String(n).padStart(12, '0')}`;
function fresh(count = 1) { let db = emptyDatabase(); for (let i = 0; i < count; i++) db = createTask(db, { title: `Task ${i}`, workspaceID: db.workspaces[0].id }); return db; }
const taskID = (db: GTDDatabase, index = 0) => db.tasks[index].id;
const encode = (value: unknown) => JSON.stringify(value);
const cloned = <T>(v: T): T => JSON.parse(JSON.stringify(v));
function withTask(db: GTDDatabase, patch: Partial<GTDTask>, index = 0) { return { ...db, tasks: db.tasks.map((t, i) => i === index ? { ...t, ...patch } : t) }; }

test('empty database has an empty useful workspace, no hidden demo data', () => {
  const db = emptyDatabase(); assert.equal(db.tasks.length, 0); assert.equal(db.workspaces.length, 1); assert.equal(db.timeEntries.length, 0);
  assert.deepEqual(parseImport(exportDatabase(db)).database, db);
});
test('demo fixture roundtrips all schema 11 collections and hierarchy', () => {
  const db = demoDatabase(now); assert.ok(db.tasks.length >= 10); assert.ok(db.workspaces.length > 1);
  assert.deepEqual(parseImport(exportDatabase(db)).database, cloned(db));
  assert.ok(taskTree(db, db.workspaces[0].id).some(row => row.depth === 2));
});
test('roundtrip preserves fractional/offset ISO text, UUID case and extension arrays', () => {
  let db = fresh(); const iso = '2026-04-12T12:35:45.123456789+02:00';
  db = withTask(db, { createdAt: iso, updatedAt: iso, note: '中文\ntext', customField: { keep: [false, 3] }, contexts: ['@desk'], tags: ['Original Case'] });
  db.extraLegacyArray = [{ id: 'opaque extension', data: ['unchanged'] }];
  db.tasks[0].id = db.tasks[0].id.toUpperCase();
  const output = parseImport(exportDatabase(db)).database;
  assert.equal(output.tasks[0].createdAt, iso); assert.equal(output.tasks[0].id, db.tasks[0].id);
  assert.deepEqual(output.extraLegacyArray, db.extraLegacyArray); assert.deepEqual(output.tasks[0].customField, db.tasks[0].customField);
});
test('legacy defaults migrate in memory without mutating input or inventing relationships', () => {
  const source = { schemaVersion: 1, workspaces: [{ id: uuid(1), name: 'Old' }], tasks: [{ id: uuid(2), workspaceID: uuid(1), title: 'Waiting', status: 'waiting', plannedStart: '2020-01-01T12:00:00Z', createdAt: '2020-01-01T00:00:00Z' }] };
  const before = encode(source), result = parseImport(before);
  assert.equal(result.database.schemaVersion, 11); assert.equal(result.database.tasks[0].actionList, 'waiting'); assert.equal(result.database.tasks[0].plannedPrecision, 'minute');
  assert.equal(result.database.tasks[0].updatedAt, '2020-01-01T00:00:00Z'); assert.equal(encode(source), before); assert.ok(result.warnings.length);
});
test('legacy missing IDs are explicitly assigned; invalid or modern missing UUIDs reject', () => {
  const legacy = { schemaVersion: 1, workspaces: [{ id: uuid(1), name: 'Old' }], tasks: [{ workspaceID: uuid(1), title: 'No ID' }] };
  assert.match(parseImport(encode(legacy)).warnings.join(' '), /assigned new UUID/);
  assert.throws(() => parseImport(encode({ ...legacy, schemaVersion: 11 })), /UUID|expected text/);
  assert.throws(() => parseImport(encode({ ...legacy, tasks: [{ ...legacy.tasks[0], id: 'broken' }] })), /UUID/);
});
test('malformed JSON, unknown envelopes/schemas and wrong container shape reject', () => {
  for (const text of ['{broken', '[]', '{}', encode({ format: 'unknown', version: 1, database: fresh() }), encode({ format: 'gtd-planner-electron', version: 2, database: fresh() }), encode({ ...fresh(), schemaVersion: 12 }), encode({ ...fresh(), schemaVersion: 0 }), encode({ ...fresh(), tasks: {} })]) assert.throws(() => parseImport(text));
});
test('null or wrong typed fields are corruption rather than silent defaults', () => {
  for (const patch of [{ status: null }, { tags: null }, { priority: false }, { order: 1.2 }, { recurrence: [] }, { createdAt: null }, { executionSlots: {} }]) assert.throws(() => parseImport(encode(withTask(fresh(), patch as never))));
});
test('unknown statuses, invalid dates/day tokens, ranges and slots reject without deletion', () => {
  const variants = [{ status: 'future' }, { deadline: '2026-02-30T00:00:00Z' }, { deadline: '2026-04-12T12:00:00' }, { completedInstances: ['2026-13-01'] }, { completedInstances: ['2026-01-01', '2026-01-01'] }, { completedInstances: ['2026-01-01'], skippedInstances: ['2026-01-01'] }, { plannedEnd: now.toISOString() }, { plannedStart: '2026-04-13T00:00:00Z', plannedEnd: '2026-04-12T00:00:00Z' }, { executionSlots: [{ id: uuid(4), start: now.toISOString(), end: now.toISOString() }] }];
  for (const patch of variants) assert.throws(() => parseImport(encode(withTask(fresh(), patch as never))));
});
test('invalid foreign keys, duplicate case-insensitive UUIDs and parent cycles reject', () => {
  let db = fresh(2);
  for (const patch of [{ workspaceID: uuid(10) }, { projectID: uuid(11) }, { parentID: uuid(12) }, { sectionID: uuid(13) }]) assert.throws(() => parseImport(encode(withTask(db, patch))), /referenced UUID/);
  assert.throws(() => parseImport(encode(withTask(db, { id: db.tasks[0].id.toUpperCase() }, 1))), /duplicate UUID/);
  db = withTask(db, { parentID: db.tasks[1].id }); db = withTask(db, { parentID: db.tasks[0].id }, 1); assert.throws(() => parseImport(encode(db)), /cycle/);
});
test('cross-workspace/project/section/category relationships reject', () => {
  let db = fresh(2); db = createWorkspace(db, 'Other'); db = createProject(db, db.workspaces[1].id, 'Other project');
  assert.throws(() => parseImport(encode(withTask(db, { projectID: db.projects[0].id }))), /another workspace/);
  db = withTask(db, { workspaceID: db.workspaces[1].id }, 1);
  assert.throws(() => parseImport(encode(withTask(db, { parentID: db.tasks[1].id }))), /share workspace/);
});
test('plain day projection honors slots, due dates, done date and half-open midnight', () => {
  let db = fresh(4), wid = db.workspaces[0].id;
  db = withTask(db, { plannedStart: '2026-04-12T23:00:00Z', plannedEnd: '2026-04-13T00:00:00Z', plannedPrecision: 'minute' });
  db = withTask(db, { executionSlots: [{ id: uuid(20), start: '2026-04-12T23:00:00Z', end: '2026-04-13T01:00:00Z' }] }, 1);
  db = withTask(db, { deadline: '2026-04-13', deadlinePrecision: 'date' }, 2);
  db = withTask(db, { status: 'done', completedAt: '2026-04-13T12:00:00Z' }, 3);
  const before = process.env.TZ; process.env.TZ = 'UTC';
  try { assert.deepEqual(tasksForDay(db, wid, '2026-04-12').map(t => t.id), [db.tasks[0].id, db.tasks[1].id]); assert.deepEqual(tasksForDay(db, wid, '2026-04-13').map(t => t.id), db.tasks.slice(1).map(t => t.id)); } finally { process.env.TZ = before; }
});
test('date-only civil range remains inclusive and stable west/east of UTC', () => {
  const db = withTask(fresh(), { plannedStart: '2026-04-12', plannedEnd: '2026-04-14', plannedPrecision: 'date' });
  const before = process.env.TZ;
  try { for (const tz of ['America/Los_Angeles', 'Asia/Tokyo', 'Europe/Berlin']) { process.env.TZ = tz; for (const day of ['2026-04-12', '2026-04-13', '2026-04-14']) assert.equal(tasksForDay(db, db.workspaces[0].id, day).length, 1); assert.equal(tasksForDay(db, db.workspaces[0].id, '2026-04-11').length, 0); assert.equal(tasksForDay(db, db.workspaces[0].id, '2026-04-15').length, 0); } } finally { process.env.TZ = before; }
});
test('legacy ISO date-only warns and follows local calendar without rewriting timestamp', () => {
  const db = withTask(fresh(), { deadline: '2026-04-12T00:00:00.123Z', deadlinePrecision: 'date' }); const before = process.env.TZ; process.env.TZ = 'America/Los_Angeles';
  try { const parsed = parseImport(exportDatabase(db)); assert.match(parsed.warnings.join(' '), /source timezone/); assert.equal(parsed.database.tasks[0].deadline, db.tasks[0].deadline); assert.equal(tasksForDay(parsed.database, db.workspaces[0].id, '2026-04-11').length, 1); } finally { process.env.TZ = before; }
});
test('DST short and long days use local next-midnight boundaries', () => {
  const before = process.env.TZ; process.env.TZ = 'America/New_York';
  try { for (const [day, s, e] of [['2026-03-08', '2026-03-09T03:30:00Z', '2026-03-09T04:00:00Z'], ['2026-11-01', '2026-11-02T04:30:00Z', '2026-11-02T05:00:00Z']]) { const db = withTask(fresh(), { executionSlots: [{ id: uuid(3), start: s, end: e }] }); assert.equal(tasksForDay(db, db.workspaces[0].id, day).length, 1); } } finally { process.env.TZ = before; }
});
test('daily recurrence anchor, completed and skipped occurrences are respected', () => {
  let db = withTask(fresh(), { recurrence: 'RRULE:FREQ=DAILY', plannedStart: '2026-04-10', plannedPrecision: 'date', skippedInstances: ['2026-04-11'] }); const wid = db.workspaces[0].id;
  assert.equal(tasksForDay(db, wid, '2026-04-09').length, 0); assert.equal(tasksForDay(db, wid, '2026-04-11').length, 0);
  db = completeTask(db, taskID(db), '2026-04-12'); const completed = db;
  db = completeTask(db, taskID(db), '2026-04-12'); assert.strictEqual(db, completed); assert.equal(db.tasks[0].status, 'inbox');
  assert.deepEqual(db.tasks[0].completedInstances, ['2026-04-12']); assert.equal(tasksForDay(db, wid, '2026-04-12').length, 1); assert.equal(tasksForDay(db, wid, '2026-04-13').length, 1);
  assert.throws(() => completeTask(db, taskID(db), '2026-04-11'), /skipped/); assert.throws(() => completeTask(db, taskID(db), '2026-04-09'), /before/); assert.throws(() => completeTask(db, taskID(db), '2099-01-01'), /today/);
});
test('unsupported recurrence is preserved, warned and never expanded as plain daily', () => {
  const db = withTask(fresh(), { recurrence: 'FREQ=DAILY;INTERVAL=3;COUNT=2', plannedStart: '2026-04-12', plannedPrecision: 'date' });
  const parsed = parseImport(exportDatabase(db)); assert.equal(parsed.database.tasks[0].recurrence, db.tasks[0].recurrence); assert.match(parsed.warnings.join(' '), /not expanded/);
  assert.equal(tasksForDay(db, db.workspaces[0].id, '2026-04-13').length, 0); assert.throws(() => completeTask(db, taskID(db)), /not supported/);
});
test('completion is idempotent; parent completion/reopen cascades with branch isolation', () => {
  let db = fresh(3), [parent, child, sibling] = db.tasks.map(t => t.id); db = updateTask(db, child, { parentID: parent }); db = completeTask(db, parent);
  assert.equal(db.tasks[0].status, 'done'); assert.equal(db.tasks[1].status, 'done'); assert.equal(db.tasks[2].status, 'inbox'); assert.strictEqual(completeTask(db, parent), db);
  db = updateTask(db, child, { status: 'open' }); assert.equal(db.tasks[0].status, 'open'); assert.equal(db.tasks[1].status, 'open'); assert.equal(db.tasks[2].id, sibling);
});
test('moves preserve subtree, update project, normalize sibling order and prevent cycles', () => {
  let db = fresh(4), [a, b, c, d] = db.tasks.map(t => t.id); db = updateTask(db, b, { parentID: a }); db = updateTask(db, c, { parentID: b });
  assert.throws(() => moveTask(db, a, c, 'inside'), /descendants/); assert.throws(() => updateTask(db, a, { parentID: c }), /descendants/);
  db = moveTask(db, a, d, 'inside'); assert.deepEqual(taskTree(db, db.workspaces[0].id).map(r => r.depth), [0, 1, 2, 3]);
  db = moveTask(db, a, d, 'before'); assert.deepEqual(taskTree(db, db.workspaces[0].id).map(r => r.task.id), [a, b, c, d]);
  db = createProject(db, db.workspaces[0].id, 'Target'); db = updateTask(db, d, { projectID: db.projects[0].id }); db = moveTask(db, a, d, 'inside');
  assert.ok(db.tasks.every(t => t.projectID === db.projects[0].id)); assert.equal(db.tasks.find(t => t.id === b)?.parentID, a);
});
test('cross-workspace drag and stable ID/workspace mutation are rejected', () => {
  let db = fresh(); db = createWorkspace(db, 'Elsewhere'); db = createTask(db, { title: 'Other', workspaceID: db.workspaces[1].id });
  assert.throws(() => moveTask(db, taskID(db), taskID(db, 1), 'inside'), /between workspaces/); assert.throws(() => updateTask(db, taskID(db), { id: uuid(10) }), /IDs/); assert.throws(() => updateTask(db, taskID(db), { workspaceID: db.workspaces[1].id }), /across workspaces/);
});
test('duplicate copies only the selected task with fresh IDs and preserved custom metadata', () => {
  let db = fresh(2); db = updateTask(db, taskID(db, 1), { parentID: taskID(db) }); db = withTask(db, { note: 'Keep me', custom: ['retain'], executionSlots: [{ id: uuid(9), start: now.toISOString(), end: '2026-04-12T11:00:00Z' }] });
  const original = cloned(db); db = duplicateTask(db, taskID(db)); assert.equal(db.tasks.length, 3); assert.equal(new Set(db.tasks.map(t => t.id)).size, 3);
  assert.equal(db.tasks[2].note, 'Keep me'); assert.deepEqual(db.tasks[2].custom, ['retain']); assert.notEqual(db.tasks[2].executionSlots[0].id, original.tasks[0].executionSlots[0].id); assert.equal(db.tasks[1].parentID, db.tasks[0].id); assert.equal(original.tasks.length, 2);
});
test('timers retain session start, exclude paused time and stop once', () => {
  let db = fresh(); db = startTimer(db, taskID(db), 'stopwatch', now); const original = db;
  assert.throws(() => startTimer(db, taskID(db), 'pomodoro', now), /current timer/);
  db = pauseTimer(db, new Date(+now + 10_250)); assert.equal(timerSeconds(db.activeTimer!, new Date(+now + 50_000)), 10.25); assert.strictEqual(pauseTimer(db), db);
  db = resumeTimer(db, new Date(+now + 60_000)); assert.equal(db.activeTimer!.sessionStartedAt, now.toISOString()); assert.strictEqual(resumeTimer(db), db);
  db = stopTimer(db, new Date(+now + 80_750)); assert.equal(db.timeEntries[0].activeSeconds, 31); assert.equal(db.timeEntries[0].startedAt, now.toISOString()); assert.equal(db.timeEntries[0].endedAt, new Date(+now + 80_750).toISOString()); assert.equal(db.activeTimer, null); assert.strictEqual(stopTimer(db), db); assert.equal(original.timeEntries.length, 0);
});
test('paused stop ends at pause and pomodoro records overtime only on explicit stop', () => {
  let db = fresh(); db = startTimer(db, taskID(db), 'pomodoro', now);
  assert.equal(db.activeTimer!.targetSeconds, 1500); assert.equal(timerSeconds(db.activeTimer!, new Date(+now + 1_600_000)), 1600); assert.equal(db.timeEntries.length, 0);
  db = pauseTimer(db, new Date(+now + 1_600_000)); db = stopTimer(db, new Date(+now + 9_000_000));
  assert.equal(db.timeEntries[0].activeSeconds, 1600); assert.equal(db.timeEntries[0].endedAt, new Date(+now + 1_600_000).toISOString()); assert.equal(db.timeEntries[0].source, 'pomodoro');
});
test('user import rejects running AND paused timers; local reopen retains exact timer', () => {
  let db = fresh(); db = startTimer(db, taskID(db), 'stopwatch', now);
  assert.throws(() => parseImport(exportDatabase(db)), /stop the running or paused timer/);
  assert.deepEqual(parseStoredDatabase(exportDatabase(db)).database.activeTimer, db.activeTimer);
  db = pauseTimer(db, new Date(+now + 30_000)); assert.throws(() => parseImport(exportDatabase(db)), /export again/);
  const reopened = parseStoredDatabase(exportDatabase(db)).database; assert.equal(timerSeconds(reopened.activeTimer!, new Date(+now + 100_000)), 30);
  db = stopTimer(reopened, new Date(+now + 100_000)); assert.equal(parseImport(exportDatabase(db)).database.timeEntries.length, 1);
});
test('local storage validates bad timers and references rather than dropping them', () => {
  let db = fresh(); db = startTimer(db, taskID(db), 'stopwatch', now);
  for (const patch of [{ taskID: uuid(1) }, { workspaceID: uuid(2) }, { startedAt: 'bad' }, { accumulatedSeconds: -1 }, { mode: 'unknown' }, { pausedAt: '2020-01-01T00:00:00Z' }]) assert.throws(() => parseStoredDatabase(encode({ ...db, activeTimer: { ...db.activeTimer, ...patch } })));
});
test('clock rollback clamps elapsed segments without erasing accumulated focus', () => {
  let db = fresh(); db = startTimer(db, taskID(db), 'stopwatch', now); db = pauseTimer(db, new Date(+now + 10_000));
  db = resumeTimer(db, new Date(+now + 20_000)); assert.equal(timerSeconds(db.activeTimer!, new Date(+now - 1_000)), 10);
  db = pauseTimer(db, new Date(+now - 1_000)); assert.equal(db.activeTimer!.accumulatedSeconds, 10); assert.equal(db.activeTimer!.pausedAt, new Date(+now + 20_000).toISOString());
});
test('trash preserves subtree, time records and fields; restoring is lossless', () => {
  let db = fresh(3); db = updateTask(db, taskID(db, 1), { parentID: taskID(db), note: 'Preserved child' });
  db = startTimer(db, taskID(db, 1), 'stopwatch', now); assert.throws(() => trashTask(db, taskID(db)), /Stop/); db = stopTimer(db, new Date(+now + 60_000));
  const original = cloned(db); db = trashTask(db, taskID(db)); assert.equal(db.tasks.length, 1); assert.equal(db.trashItems[0].tasks.length, 2); assert.equal(db.timeEntries.length, 0); assert.equal(db.trashItems[0].timeEntries.length, 1);
  db = parseImport(exportDatabase(db)).database; db = restoreTrash(db, db.trashItems[0].id); assert.equal(db.trashItems.length, 0);
  assert.deepEqual([...db.tasks].sort((a, b) => a.id.localeCompare(b.id)), [...original.tasks].sort((a, b) => a.id.localeCompare(b.id))); assert.deepEqual(db.timeEntries, original.timeEntries);
});
test('separately trashed child/parent snapshots roundtrip and require ordered restoration', () => {
  let db = fresh(2), [parent, child] = db.tasks.map(t => t.id); db = updateTask(db, child, { parentID: parent });
  db = trashTask(db, child); const childTrash = db.trashItems[0].id; db = trashTask(db, parent); const parentTrash = db.trashItems[1].id;
  db = parseImport(exportDatabase(db)).database; assert.throws(() => restoreTrash(db, childTrash), /parent first/);
  db = restoreTrash(db, parentTrash); db = restoreTrash(db, childTrash); assert.equal(db.tasks.length, 2); assert.equal(db.tasks.find(t => t.id === child)?.parentID, parent);
});
test('restore refuses ID collisions and import refuses malformed archive payload', () => {
  let db = fresh(); const original = db.tasks[0]; db = trashTask(db, original.id);
  const collision = { ...db, tasks: [original] }; assert.throws(() => restoreTrash(collision, db.trashItems[0].id), /overwrite/);
  const malformed = cloned(db); malformed.trashItems[0].tasks = []; assert.throws(() => parseImport(encode(malformed)), /missing task snapshot/);
});
test('legacy project/workspace archive metadata and arrays survive roundtrip', () => {
  let db = fresh(); const archivedID = uuid(800), projectID = uuid(801), tagCategoryID = uuid(802);
  db.trashItems.push({ id: uuid(803), kind: 'workspace', objectID: archivedID, workspaceID: archivedID, name: 'Archived', deletedAt: now.toISOString(), workspace: { id: archivedID, name: 'Archived', symbolName: 'house', colorHex: '#000000' }, projectCategories: [], projects: [{ id: projectID, workspaceID: archivedID, name: 'Archived project', colorHex: '#123456', category: '', note: 'retain', symbolName: 'folder', order: 5 }], tasks: [], timeEntries: [], projectSections: [], tagCategories: [{ id: tagCategoryID, workspaceID: archivedID, name: 'Category', colorHex: '#123456', order: 0, createdAt: now.toISOString(), updatedAt: now.toISOString() }], tagDefinitions: [{ id: uuid(804), workspaceID: archivedID, categoryID: tagCategoryID, name: 'Metadata', colorHex: '#112233', note: 'keep', order: 0, createdAt: now.toISOString(), updatedAt: now.toISOString() }], customArchiveMetadata: [1, 2] });
  const exported = exportDatabase(db); const parsed = parseImport(exported).database; assert.deepEqual(parsed.trashItems, db.trashItems);
  const restored = restoreTrash(parsed, uuid(803)); assert.equal(restored.workspaces.length, 2); assert.equal(restored.projects[0].note, 'retain'); assert.equal(restored.tagDefinitions[0].name, 'Metadata');
});
test('tree projection scales to deep hierarchies without recursion overflow', () => {
  const db = fresh(), template = db.tasks[0]; db.tasks = Array.from({ length: 5000 }, (_, i) => ({ ...template, id: uuid(i + 1), parentID: i ? uuid(i) : null, order: i }));
  validateDatabase(db); const rows = taskTree(db, db.workspaces[0].id); assert.equal(rows.length, 5000); assert.equal(rows.at(-1)?.depth, 4999);
});
test('date keys use civil components rather than UTC serialization', () => {
  const before = process.env.TZ; process.env.TZ = 'Pacific/Auckland'; try { assert.equal(dayKey(new Date('2026-04-12T18:00:00Z')), '2026-04-13'); } finally { process.env.TZ = before; }
});
