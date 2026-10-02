import type { GTDDatabase, GTDTask, ActiveTimer, Preserved } from './types.js';
import { isDayKey, isISO, localDate, supportsDailyRecurrence } from './dates.js';

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const own = (o: Preserved, k: string) => Object.prototype.hasOwnProperty.call(o, k);
export const idKey = (id: string) => id.toLowerCase();
export const sameID = (a?: string | null, b?: string | null) => a == null ? b == null : b != null && idKey(a) === idKey(b);
function fail(path: string, reason: string): never { throw new Error(`${path}: ${reason}. Import has not changed your data.`); }
function record(v: unknown, path: string): Preserved { if (!v || typeof v !== 'object' || Array.isArray(v)) fail(path, 'expected an object'); return v as Preserved; }
function str(v: unknown, path: string): string { if (typeof v !== 'string') fail(path, 'expected text'); return v; }
function num(v: unknown, path: string, integer = false): number { if (typeof v !== 'number' || !Number.isFinite(v) || (integer && !Number.isSafeInteger(v))) fail(path, 'expected a finite' + (integer ? ' integer' : ' number')); return v; }
function uuid(v: unknown, path: string): string { const s = str(v, path); if (!UUID.test(s)) fail(path, 'expected a valid UUID'); return s; }
function choice(v: unknown, values: readonly string[], path: string): string { const s = str(v, path); if (!values.includes(s)) fail(path, `unsupported value ${JSON.stringify(s)}`); return s; }
function array(v: unknown, path: string): unknown[] { if (!Array.isArray(v)) fail(path, 'expected an array'); return v; }
function date(v: unknown, path: string, civil = false): string { if (!isISO(v) && !(civil && isDayKey(v))) fail(path, `expected ${civil ? 'a local YYYY-MM-DD date or ' : ''}an ISO timestamp with timezone`); return v as string; }
const nullableFields = new Set(['projectID', 'sectionID', 'parentID', 'categoryID', 'taskID', 'workspaceID', 'plannedStart', 'plannedEnd', 'deadline', 'completedAt', 'pausedAt', 'targetSeconds', 'phase', 'pomodoroPhase', 'activeSeconds']);
function optional(o: Preserved, key: string, check: (v: unknown, p: string) => unknown, path: string) {
  if (!own(o, key)) return;
  if (o[key] == null && nullableFields.has(key)) return;
  check(o[key], `${path}.${key}`);
}
function defaults(o: Preserved, values: Preserved): Preserved { return { ...values, ...o }; }
function items(o: Preserved, key: string, path: string): unknown[] { return own(o, key) ? array(o[key], `${path}.${key}`) : []; }
function strings(o: Preserved, key: string, path: string): string[] { return items(o, key, path).map((v, i) => str(v, `${path}.${key}[${i}]`)); }
function ids(o: Preserved, key: string, path: string): string[] { return items(o, key, path).map((v, i) => uuid(v, `${path}.${key}[${i}]`)); }
function unique(values: { id: string }[], path: string) { const seen = new Set<string>(); for (const v of values) { const k = idKey(v.id); if (seen.has(k)) fail(path, `duplicate UUID ${v.id}`); seen.add(k); } }
function entity(v: unknown, p: string, version: number, warnings: Set<string>): Preserved {
  const o = { ...record(v, p) };
  if (!own(o, 'id') && version < 11) { o.id = crypto.randomUUID(); warnings.add('Older records without an ID were assigned new UUIDs. Existing IDs were preserved.'); }
  uuid(o.id, `${p}.id`); return o;
}
const statusValues = ['inbox', 'open', 'in-progress', 'waiting', 'someday', 'done', 'cancelled'];
function task(v: unknown, p: string, version: number, warnings: Set<string>): GTDTask {
  const o = entity(v, p, version, warnings); str(o.title, `${p}.title`); uuid(o.workspaceID, `${p}.workspaceID`);
  for (const k of ['projectID', 'sectionID', 'parentID']) optional(o, k, uuid, p);
  optional(o, 'status', (v, p) => choice(v, statusValues, p), p);
  optional(o, 'priority', (v, p) => choice(v, ['none', 'low', 'medium', 'high'], p), p);
  optional(o, 'actionList', (v, p) => choice(v, ['next-action', 'waiting', 'someday-maybe'], p), p);
  for (const k of ['plannedPrecision', 'deadlinePrecision']) optional(o, k, (v, p) => choice(v, ['none', 'date', 'minute'], p), p);
  optional(o, 'planRangeIntent', (v, p) => choice(v, ['progress', 'complete-within'], p), p);
  for (const k of ['recurrence', 'note']) optional(o, k, str, p);
  for (const k of ['createdAt', 'updatedAt', 'completedAt']) optional(o, k, date, p);
  for (const k of ['plannedStart', 'plannedEnd']) optional(o, k, (v, p) => date(v, p, o.plannedPrecision === 'date'), p);
  optional(o, 'deadline', (v, p) => date(v, p, o.deadlinePrecision === 'date'), p);
  optional(o, 'order', (v, p) => num(v, p, true), p);
  const tags = strings(o, 'tags', p), contexts = strings(o, 'contexts', p);
  const completedInstances = strings(o, 'completedInstances', p), skippedInstances = strings(o, 'skippedInstances', p);
  for (const [field, days] of [['completedInstances', completedInstances], ['skippedInstances', skippedInstances]] as const) {
    for (const day of days) if (!isDayKey(day)) fail(`${p}.${field}`, `invalid day ${day}`);
    if (new Set(days).size !== days.length) fail(`${p}.${field}`, 'duplicate day tokens');
  }
  if (completedInstances.some(day => skippedInstances.includes(day))) fail(p, 'a daily occurrence cannot be both completed and skipped');
  const executionSlots = items(o, 'executionSlots', p).map((v, i) => {
    const path = `${p}.executionSlots[${i}]`, slot = entity(v, path, version, warnings);
    date(slot.start, `${path}.start`); date(slot.end, `${path}.end`);
    if (Date.parse(slot.end as string) <= Date.parse(slot.start as string)) fail(path, 'execution end must be after start');
    return slot as unknown as GTDTask['executionSlots'][number];
  });
  unique(executionSlots, `${p}.executionSlots`);
  if (o.plannedEnd && !o.plannedStart) fail(p, 'planned end needs a planned start');
  if (o.plannedStart && o.plannedEnd && localDate(o.plannedEnd as string) < localDate(o.plannedStart as string)) fail(p, 'planned end is before start');
  if (o.plannedPrecision && o.plannedPrecision !== 'none' && !o.plannedStart) fail(p, 'planned precision needs a planned start');
  if (o.deadlinePrecision && o.deadlinePrecision !== 'none' && !o.deadline) fail(p, 'deadline precision needs a deadline');
  const status = o.status ?? 'inbox';
  // Missing historical dates use one deterministic fallback, never the import time.
  const createdAt = o.createdAt ?? o.updatedAt ?? '1970-01-01T00:00:00Z';
  if (!o.createdAt) warnings.add('Missing legacy creation dates use the existing updated date, or 1970-01-01 when neither timestamp exists.');
  const result = defaults(o, { status, priority: 'none', actionList: status === 'waiting' ? 'waiting' : status === 'someday' ? 'someday-maybe' : 'next-action', tags, contexts,
    plannedPrecision: o.plannedStart ? 'minute' : 'none', planRangeIntent: 'progress', executionSlots, deadlinePrecision: 'none', recurrence: '', note: '', createdAt, updatedAt: createdAt, order: 0, completedInstances, skippedInstances }) as unknown as GTDTask;
  result.executionSlots = executionSlots;
  if (result.recurrence.trim() && !supportsDailyRecurrence(result)) warnings.add('Some recurrence rules are preserved but not expanded: this prototype only projects FREQ=DAILY with optional INTERVAL=1.');
  if ((result.plannedPrecision === 'date' && result.plannedStart && isISO(result.plannedStart)) || (result.deadlinePrecision === 'date' && result.deadline && isISO(result.deadline))) warnings.add('Legacy date-only values are ISO instants without a source timezone. Their local day follows this device’s timezone; review dates after a timezone change. Original strings are preserved.');
  return result;
}
function named(v: unknown, p: string, version: number, warnings: Set<string>, kind: string): Preserved {
  const o = entity(v, p, version, warnings); str(o.name, `${p}.name`);
  if (kind !== 'workspace') uuid(o[kind === 'section' ? 'projectID' : 'workspaceID'], `${p}.${kind === 'section' ? 'projectID' : 'workspaceID'}`);
  for (const k of ['symbolName', 'colorHex', 'category', 'note']) optional(o, k, str, p);
  optional(o, 'order', (v, p) => num(v, p, true), p); optional(o, 'categoryID', uuid, p);
  for (const k of ['createdAt', 'updatedAt']) optional(o, k, date, p);
  const values: Preserved = kind === 'workspace' ? { symbolName: 'square.grid.2x2', colorHex: '#2563EB' } : { colorHex: '#2563EB', order: 0 };
  if (kind === 'project') Object.assign(values, { category: '', symbolName: 'folder', note: '' });
  if (kind === 'tagCategory' || kind === 'tagDefinition') Object.assign(values, { createdAt: '1970-01-01T00:00:00Z', updatedAt: o.createdAt ?? '1970-01-01T00:00:00Z' });
  if (kind === 'tagDefinition') values.note = '';
  return defaults(o, values);
}
function timeEntry(v: unknown, p: string, version: number, warnings: Set<string>): Preserved {
  const o = entity(v, p, version, warnings); uuid(o.workspaceID, `${p}.workspaceID`); optional(o, 'taskID', uuid, p);
  str(o.title, `${p}.title`); date(o.startedAt, `${p}.startedAt`); date(o.endedAt, `${p}.endedAt`);
  if (Date.parse(o.endedAt as string) < Date.parse(o.startedAt as string)) fail(p, 'time entry ends before it starts');
  choice(o.source, ['stopwatch', 'pomodoro', 'manual'], `${p}.source`); optional(o, 'pomodoroPhase', (v, p) => choice(v, ['focus', 'shortBreak', 'longBreak'], p), p);
  optional(o, 'note', str, p); optional(o, 'activeSeconds', num, p);
  if (typeof o.activeSeconds === 'number' && o.activeSeconds < 0) fail(p, 'active seconds cannot be negative');
  return defaults(o, { note: '' });
}
function timer(v: unknown, p: string): ActiveTimer {
  const o = record(v, p); choice(o.mode, ['stopwatch', 'pomodoro'], `${p}.mode`);
  optional(o, 'workspaceID', uuid, p); optional(o, 'taskID', uuid, p); str(o.title, `${p}.title`);
  date(o.startedAt, `${p}.startedAt`); optional(o, 'sessionStartedAt', date, p); optional(o, 'pausedAt', date, p);
  for (const k of ['accumulatedSeconds', 'targetSeconds']) { optional(o, k, num, p); if (typeof o[k] === 'number' && (o[k] as number) < 0) fail(`${p}.${k}`, 'cannot be negative'); }
  optional(o, 'focusCount', (v, p) => num(v, p, true), p); optional(o, 'phase', (v, p) => choice(v, ['focus', 'shortBreak', 'longBreak'], p), p);
  const result = defaults(o, { sessionStartedAt: o.startedAt, accumulatedSeconds: 0, focusCount: 0 }) as unknown as ActiveTimer;
  if (Date.parse(result.sessionStartedAt) > Date.parse(result.startedAt)) fail(p, 'session starts after current timer segment');
  if (result.pausedAt && Date.parse(result.pausedAt) < Date.parse(result.startedAt)) fail(p, 'pause precedes current timer segment');
  return result;
}
/** Validates before defaulting; never drops records to repair an import. */
export function validateDatabase(value: unknown, allowActiveTimer = true): { database: GTDDatabase; warnings: string[] } {
  const raw = record(value, 'database'), warnings = new Set<string>();
  const version = own(raw, 'schemaVersion') ? num(raw.schemaVersion, 'schemaVersion', true) : 1;
  if (version < 1 || version > 11) fail('schemaVersion', `unsupported schema ${version}; this prototype supports 1–11`);
  if (!own(raw, 'workspaces') || !own(raw, 'tasks')) fail('database', 'workspaces and tasks arrays are required');
  if (!allowActiveTimer && raw.activeTimer != null) fail('activeTimer', 'stop the running or paused timer in the source app, then export again before importing');
  const r: Preserved = { ...raw, schemaVersion: 11 };
  for (const [field, kind] of [['workspaces', 'workspace'], ['projects', 'project'], ['projectCategories', 'category'], ['projectSections', 'section'], ['tagCategories', 'tagCategory'], ['tagDefinitions', 'tagDefinition']]) {
    r[field] = items(raw, field, 'database').map((v, i) => named(v, `${field}[${i}]`, version, warnings, kind));
  }
  r.tasks = items(raw, 'tasks', 'database').map((v, i) => task(v, `tasks[${i}]`, version, warnings));
  r.timeEntries = items(raw, 'timeEntries', 'database').map((v, i) => timeEntry(v, `timeEntries[${i}]`, version, warnings));
  r.workspaceOrder = ids(raw, 'workspaceOrder', 'database'); r.pinnedWorkspaceIDs = ids(raw, 'pinnedWorkspaceIDs', 'database');
  if (own(raw, 'workspaceShortcutsConfigured') && typeof raw.workspaceShortcutsConfigured !== 'boolean') fail('workspaceShortcutsConfigured', 'expected a boolean');
  r.workspaceShortcutsConfigured = raw.workspaceShortcutsConfigured ?? false;
  r.workspaceSortMode = own(raw, 'workspaceSortMode') ? choice(raw.workspaceSortMode, ['manual', 'name', 'recent'], 'workspaceSortMode') : 'manual';
  const opened = own(raw, 'workspaceLastOpenedAt') ? record(raw.workspaceLastOpenedAt, 'workspaceLastOpenedAt') : {};
  for (const [id, d] of Object.entries(opened)) { uuid(id, 'workspaceLastOpenedAt key'); date(d, `workspaceLastOpenedAt.${id}`); }
  r.workspaceLastOpenedAt = opened;
  if (raw.activeTimer != null) r.activeTimer = timer(raw.activeTimer, 'activeTimer');
  r.activityLog = items(raw, 'activityLog', 'database').map((v, i) => {
    const p = `activityLog[${i}]`, o = entity(v, p, version, warnings); date(o.timestamp, `${p}.timestamp`); str(o.action, `${p}.action`); str(o.target, `${p}.target`); optional(o, 'detail', str, p); return defaults(o, { detail: '' });
  });
  r.trashItems = items(raw, 'trashItems', 'database').map((v, i) => {
    const p = `trashItems[${i}]`, o = entity(v, p, version, warnings);
    choice(o.kind, ['workspace', 'project', 'task'], `${p}.kind`); uuid(o.objectID, `${p}.objectID`); uuid(o.workspaceID, `${p}.workspaceID`); str(o.name, `${p}.name`); date(o.deletedAt, `${p}.deletedAt`);
    for (const [field, kind] of [['projects', 'project'], ['projectCategories', 'category'], ['projectSections', 'section'], ['tagCategories', 'tagCategory'], ['tagDefinitions', 'tagDefinition']]) {
      if (o[field] == null && ['projectSections', 'tagCategories', 'tagDefinitions'].includes(field)) continue;
      o[field] = items(o, field, p).map((item, j) => named(item, `${p}.${field}[${j}]`, version, warnings, kind));
    }
    o.tasks = items(o, 'tasks', p).map((v, j) => task(v, `${p}.tasks[${j}]`, version, warnings));
    o.timeEntries = items(o, 'timeEntries', p).map((v, j) => timeEntry(v, `${p}.timeEntries[${j}]`, version, warnings));
    if (o.workspace != null) o.workspace = named(o.workspace, `${p}.workspace`, version, warnings, 'workspace');
    if (o.project != null) o.project = named(o.project, `${p}.project`, version, warnings, 'project');
    return o;
  });
  const db = r as unknown as GTDDatabase;
  validateRelationships(db);
  const allArchived = {
    workspaces: db.trashItems.flatMap(t => t.workspace ? [t.workspace] : []),
    projects: db.trashItems.flatMap(t => [...t.projects, ...(t.project ? [t.project] : [])]),
    projectCategories: db.trashItems.flatMap(t => t.projectCategories), projectSections: db.trashItems.flatMap(t => t.projectSections ?? []),
    tagCategories: db.trashItems.flatMap(t => t.tagCategories ?? []), tagDefinitions: db.trashItems.flatMap(t => t.tagDefinitions ?? []),
    tasks: db.trashItems.flatMap(t => t.tasks), timeEntries: db.trashItems.flatMap(t => t.timeEntries)
  };
  const distinct = <T extends { id: string }>(rows: T[]): T[] => [...new Map(rows.map(t => [idKey(t.id), t])).values()];
  for (const archive of db.trashItems) {
    // Snapshots can refer to surviving live parents. Prefer their own snapshot
    // records when IDs overlap; restoration separately rejects any collision.
    const merge = <T extends { id: string }>(live: T[], stored: T[]) => [...live.filter(a => !stored.some(b => sameID(a.id, b.id))), ...stored];
    const archived = { ...db,
      workspaces: merge(merge(db.workspaces, distinct(allArchived.workspaces)), archive.workspace ? [archive.workspace] : []),
      projects: merge(merge(db.projects, distinct(allArchived.projects)), [...archive.projects, ...(archive.project ? [archive.project] : [])].filter((p, i, all) => all.findIndex(q => sameID(p.id, q.id)) === i)),
      projectCategories: merge(merge(db.projectCategories, distinct(allArchived.projectCategories)), archive.projectCategories), projectSections: merge(merge(db.projectSections, distinct(allArchived.projectSections)), archive.projectSections ?? []),
      tagCategories: merge(merge(db.tagCategories, distinct(allArchived.tagCategories)), archive.tagCategories ?? []), tagDefinitions: merge(merge(db.tagDefinitions, distinct(allArchived.tagDefinitions)), archive.tagDefinitions ?? []),
      tasks: merge(merge(db.tasks, distinct(allArchived.tasks)), archive.tasks), timeEntries: merge(merge(db.timeEntries, distinct(allArchived.timeEntries)), archive.timeEntries),
      activeTimer: null, trashItems: [], activityLog: [], workspaceOrder: [], pinnedWorkspaceIDs: [], workspaceLastOpenedAt: {}
    };
    for (const field of ['tasks', 'projects', 'projectCategories', 'projectSections', 'tagCategories', 'tagDefinitions', 'timeEntries'] as const) unique(archive[field] ?? [], `trash.${field}`);
    validateRelationships(archived, `trash ${archive.name}`);
    const root = archive.kind === 'workspace' ? archive.workspace : archive.kind === 'project' ? archive.project ?? archive.projects.find(p => sameID(p.id, archive.objectID)) : archive.tasks.find(t => sameID(t.id, archive.objectID));
    if (!root || !sameID(root.id, archive.objectID)) fail('trashItems', `missing ${archive.kind} snapshot for ${archive.name}`);
  }
  if (version < 11) warnings.add(`Legacy schema ${version} was upgraded in memory to schema 11 by adding missing defaults; no records were deleted.`);
  return { database: db, warnings: [...warnings] };
}
function validateRelationships(db: GTDDatabase, prefix = 'database') {
  for (const field of ['workspaces', 'projects', 'projectCategories', 'projectSections', 'tagCategories', 'tagDefinitions', 'tasks', 'timeEntries', 'trashItems', 'activityLog'] as const) unique(db[field], `${prefix}.${field}`);
  const map = <T extends { id: string }>(rows: T[]) => new Map(rows.map(t => [idKey(t.id), t]));
  const workspaces = map(db.workspaces), projects = map(db.projects), sections = map(db.projectSections), tags = map(db.tagCategories), tasks = map(db.tasks);
  const ref = <T>(m: Map<string, T>, id: string, path: string): T => { const value = m.get(idKey(id)); if (!value) fail(path, `missing referenced UUID ${id}`); return value; };
  for (const p of [...db.projects, ...db.projectCategories, ...db.tagCategories, ...db.tagDefinitions]) ref(workspaces, p.workspaceID, prefix + '.workspaceID');
  for (const s of db.projectSections) ref(projects, s.projectID, prefix + '.section.projectID');
  for (const t of db.tagDefinitions) if (t.categoryID && !sameID(ref(tags, t.categoryID, 'tag.categoryID').workspaceID, t.workspaceID)) fail('tag.categoryID', 'category belongs to another workspace');
  for (const task of db.tasks) {
    ref(workspaces, task.workspaceID, `task ${task.title}.workspaceID`);
    if (task.projectID && !sameID(ref(projects, task.projectID, `task ${task.title}.projectID`).workspaceID, task.workspaceID)) fail('task.projectID', 'project belongs to another workspace');
    if (task.sectionID && !sameID(ref(sections, task.sectionID, 'task.sectionID').projectID, task.projectID)) fail('task.sectionID', 'section belongs to another project');
    if (task.parentID) { const parent = ref(tasks, task.parentID, `task ${task.title}.parentID`); if (!sameID(parent.workspaceID, task.workspaceID) || !sameID(parent.projectID, task.projectID)) fail('task.parentID', 'parent must share workspace and project'); }
  }
  // Iterative colors avoid stack overflow for deeply nested but valid trees.
  const finished = new Set<string>();
  for (const task of db.tasks) {
    let current: GTDTask | undefined = task; const path = new Set<string>();
    while (current && !finished.has(idKey(current.id))) {
      const id = idKey(current.id); if (path.has(id)) fail('tasks', `parent cycle involving ${current.title}`);
      path.add(id); current = current.parentID ? tasks.get(idKey(current.parentID)) : undefined;
    }
    for (const id of path) finished.add(id);
  }
  for (const entry of db.timeEntries) { ref(workspaces, entry.workspaceID, 'timeEntry.workspaceID'); if (entry.taskID && !sameID(ref(tasks, entry.taskID, 'timeEntry.taskID').workspaceID, entry.workspaceID)) fail('timeEntry.taskID', 'task belongs to another workspace'); }
  for (const field of ['workspaceOrder', 'pinnedWorkspaceIDs'] as const) { const seen = new Set<string>(); for (const id of db[field]) { ref(workspaces, id, field); if (seen.has(idKey(id))) fail(field, 'duplicate workspace ID'); seen.add(idKey(id)); } }
  for (const id of Object.keys(db.workspaceLastOpenedAt)) ref(workspaces, id, 'workspaceLastOpenedAt');
  const t = db.activeTimer;
  if (t) { if (t.workspaceID) ref(workspaces, t.workspaceID, 'activeTimer.workspaceID'); if (t.taskID) { const task = ref(tasks, t.taskID, 'activeTimer.taskID'); if (t.workspaceID && !sameID(task.workspaceID, t.workspaceID)) fail('activeTimer', 'timer task belongs to another workspace'); } }
}
function parse(text: string, allowTimer: boolean) {
  let parsed: unknown;
  try { parsed = JSON.parse(text); } catch { throw new Error('The file is not valid JSON. Import has not changed your data.'); }
  const root = record(parsed, 'file');
  if (own(root, 'format') || own(root, 'database')) {
    if (root.format !== 'gtd-planner-electron' || root.version !== 1) fail('file', 'unsupported export format or version');
    return validateDatabase(root.database, allowTimer);
  }
  return validateDatabase(root, allowTimer);
}
export function parseImport(text: string) { return parse(text, false); }
/** Only for reopening this app’s own durable local store, never user-file import. */
export function parseStoredDatabase(text: string) { return parse(text, true); }
export function exportDatabase(db: GTDDatabase): string {
  validateDatabase(db, true);
  return JSON.stringify({ format: 'gtd-planner-electron', version: 1, database: db }, null, 2);
}
