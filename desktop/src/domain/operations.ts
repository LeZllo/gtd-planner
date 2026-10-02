import type { GTDDatabase, GTDTask, ActiveTimer, TimerMode, TrashItem } from './types.js';
import { dayKey, dateDay, dayBounds, localDate, supportsDailyRecurrence, isDayKey, deadlineInstant } from './dates.js';
import { idKey, sameID, validateDatabase } from './validation.js';

const uuid = () => crypto.randomUUID();
const instant = (date = new Date()) => { if (!Number.isFinite(date.getTime())) throw new Error('Invalid timestamp'); return date.toISOString(); };
const lookup = (db: GTDDatabase, id: string) => { const task = db.tasks.find(t => sameID(t.id, id)); if (!task) throw new Error('Task was not found'); return task; };
const sorted = (tasks: GTDTask[]) => tasks.map((task, index) => ({ task, index })).sort((a, b) => a.task.order - b.task.order || a.index - b.index).map(v => v.task);
const checked = (db: GTDDatabase) => { validateDatabase(db); return db; };
export function emptyDatabase(): GTDDatabase {
  const workspaceID = uuid();
  return { schemaVersion: 11, workspaces: [{ id: workspaceID, name: 'Personal', symbolName: 'house', colorHex: '#2563EB' }], workspaceOrder: [workspaceID], pinnedWorkspaceIDs: [workspaceID], workspaceShortcutsConfigured: true, workspaceSortMode: 'manual', workspaceLastOpenedAt: {}, projects: [], projectCategories: [], projectSections: [], tagCategories: [], tagDefinitions: [], tasks: [], timeEntries: [], activeTimer: null, trashItems: [], activityLog: [] };
}
export function createWorkspace(db: GTDDatabase, name: string): GTDDatabase {
  if (!name.trim()) throw new Error('Workspace name is required');
  const id = uuid(); return checked({ ...db, workspaces: [...db.workspaces, { id, name: name.trim(), symbolName: 'square.grid.2x2', colorHex: '#2563EB' }], workspaceOrder: [...db.workspaceOrder, id] });
}
export function createProject(db: GTDDatabase, workspaceID: string, name: string): GTDDatabase {
  if (!name.trim()) throw new Error('Project name is required');
  if (!db.workspaces.some(w => sameID(w.id, workspaceID))) throw new Error('Workspace was not found');
  return checked({ ...db, projects: [...db.projects, { id: uuid(), workspaceID, name: name.trim(), category: '', symbolName: 'folder', colorHex: '#2563EB', note: '', order: db.projects.filter(p => sameID(p.workspaceID, workspaceID)).length }] });
}
export function createTask(db: GTDDatabase, input: { title: string; workspaceID: string; projectID?: string; parentID?: string }): GTDDatabase {
  if (!input.title.trim()) throw new Error('Task title is required');
  const parent = input.parentID ? lookup(db, input.parentID) : undefined;
  if (parent && !sameID(parent.workspaceID, input.workspaceID)) throw new Error('Parent belongs to another workspace');
  if (parent && input.projectID && !sameID(parent.projectID, input.projectID)) throw new Error('Parent belongs to another project');
  const now = instant(), projectID = parent?.projectID ?? input.projectID;
  const task: GTDTask = { id: uuid(), title: input.title.trim(), workspaceID: input.workspaceID, projectID, parentID: parent?.id, sectionID: parent?.sectionID,
    status: projectID || parent ? 'open' : 'inbox', priority: 'none', actionList: 'next-action', tags: [], contexts: [], plannedPrecision: 'none', planRangeIntent: 'progress', executionSlots: [], deadlinePrecision: 'none', recurrence: '', note: '', createdAt: now, updatedAt: now, order: Math.max(-1, ...db.tasks.filter(t => sameID(t.workspaceID, input.workspaceID) && sameID(t.projectID, projectID) && sameID(t.parentID, parent?.id)).map(t => t.order)) + 1, completedInstances: [], skippedInstances: [] };
  return checked({ ...db, tasks: [...db.tasks, task] });
}
function subtreeIDs(db: GTDDatabase, root: string): Set<string> {
  const ids = new Set([idKey(root)]), children = new Map<string, string[]>();
  for (const t of db.tasks) if (t.parentID) { const key = idKey(t.parentID); const list = children.get(key); if (list) list.push(idKey(t.id)); else children.set(key, [idKey(t.id)]); }
  const queue = [idKey(root)]; for (let i = 0; i < queue.length; i++) for (const id of children.get(queue[i]) ?? []) if (!ids.has(id)) { ids.add(id); queue.push(id); }
  return ids;
}
export function updateTask(db: GTDDatabase, id: string, patch: Partial<GTDTask>, at = new Date()): GTDDatabase {
  const previous = lookup(db, id);
  if (patch.id != null && !sameID(patch.id, id)) throw new Error('Stable task IDs cannot change');
  if (patch.workspaceID != null && !sameID(patch.workspaceID, previous.workspaceID)) throw new Error('Moving tasks across workspaces is not supported');
  if (patch.title !== undefined && !patch.title.trim()) throw new Error('Task title is required');
  const now = instant(at); let next = { ...previous, ...patch, id: previous.id, workspaceID: previous.workspaceID, updatedAt: now };
  const descendants = subtreeIDs(db, id);
  if (next.parentID && descendants.has(idKey(next.parentID))) throw new Error('A task cannot be moved inside itself or its descendants');
  if (Object.prototype.hasOwnProperty.call(patch, 'parentID') && next.parentID) {
    const parent = lookup(db, next.parentID); if (!sameID(parent.workspaceID, next.workspaceID)) throw new Error('Parent belongs to another workspace');
    next = { ...next, projectID: parent.projectID, sectionID: parent.sectionID };
  }
  const projectChanged = !sameID(next.projectID, previous.projectID);
  if (projectChanged) {
    if (next.parentID && !sameID(lookup(db, next.parentID).projectID, next.projectID)) throw new Error('Move the parent too, or detach this task before changing its project');
    if (!Object.prototype.hasOwnProperty.call(patch, 'sectionID')) next.sectionID = null;
  }
  const statusChanged = next.status !== previous.status;
  if (statusChanged) next.completedAt = next.status === 'done' ? now : null;
  const reopen = statusChanged && previous.status === 'done' && next.status !== 'done' && next.status !== 'cancelled';
  const ancestors = new Set<string>();
  if (statusChanged && next.status !== 'done' && next.status !== 'cancelled') {
    let parentID = next.parentID; while (parentID && !ancestors.has(idKey(parentID))) { ancestors.add(idKey(parentID)); parentID = lookup(db, parentID).parentID; }
  }
  const tasks = db.tasks.map(t => {
    if (sameID(t.id, id)) return next;
    let result = t;
    if (descendants.has(idKey(t.id))) {
      if (projectChanged) result = { ...result, projectID: next.projectID, sectionID: next.sectionID, updatedAt: now };
      if (statusChanged && next.status === 'done') result = { ...result, status: 'done', completedAt: now, updatedAt: now };
      else if (reopen) result = { ...result, status: 'open', completedAt: null, updatedAt: now };
    }
    if (ancestors.has(idKey(t.id)) && t.status === 'done') result = { ...result, status: 'open', completedAt: null, updatedAt: now };
    return result;
  });
  return checked({ ...db, tasks });
}
/** Pure projection: no timestamp mutation or per-tick persistence. */
export function tasksForDay(db: GTDDatabase, workspaceID: string, day: string, now = new Date()): GTDTask[] {
  const [start, end] = dayBounds(day), today = dayKey(now);
  const overlaps = (s: string, e?: string | null) => { const a = localDate(s).getTime(), b = e ? localDate(e).getTime() : a; return b > a ? a < end && b > start : a >= start && a < end; };
  return sorted(db.tasks.filter(task => {
    if (!sameID(task.workspaceID, workspaceID) || task.status === 'cancelled') return false;
    const daily = supportsDailyRecurrence(task);
    if (daily && task.completedInstances.includes(day)) return true;
    if (!daily && task.status === 'done') return !!task.completedAt && dateDay(task.completedAt) === day;
    if (task.status === 'done') return false;
    if (daily) return !task.skippedInstances.includes(day) && (!task.plannedStart || dateDay(task.plannedStart) <= day);
    // Date-only end is an inclusive civil day; minute ranges are half-open.
    if (task.plannedStart) {
      if (task.plannedPrecision === 'date') { if (dateDay(task.plannedStart) <= day && day <= dateDay(task.plannedEnd ?? task.plannedStart)) return true; }
      else if (overlaps(task.plannedStart, task.plannedEnd)) return true;
    }
    if (task.executionSlots.some(slot => overlaps(slot.start, slot.end))) return true;
    if (task.deadline) return dateDay(task.deadline) === day || (day === today && deadlineInstant(task)! < now.getTime());
    return false;
  }));
}
export function taskTree(db: GTDDatabase, workspaceID: string, projectID?: string): Array<{ task: GTDTask; depth: number }> {
  const tasks = sorted(db.tasks.filter(t => sameID(t.workspaceID, workspaceID) && (projectID === undefined || sameID(t.projectID, projectID))));
  const ids = new Set(tasks.map(t => idKey(t.id))), children = new Map<string, GTDTask[]>();
  const roots: GTDTask[] = [];
  for (const task of tasks) {
    if (!task.parentID || !ids.has(idKey(task.parentID))) roots.push(task);
    else { const key = idKey(task.parentID); const list = children.get(key); if (list) list.push(task); else children.set(key, [task]); }
  }
  const result: Array<{ task: GTDTask; depth: number }> = [], visited = new Set<string>(), stack = roots.reverse().map(task => ({ task, depth: 0 }));
  while (stack.length) { const item = stack.pop()!; if (visited.has(idKey(item.task.id))) throw new Error('Task hierarchy contains a cycle'); visited.add(idKey(item.task.id)); result.push(item); for (const child of [...(children.get(idKey(item.task.id)) ?? [])].reverse()) stack.push({ task: child, depth: item.depth + 1 }); }
  if (result.length !== tasks.length) throw new Error('Task hierarchy contains a cycle');
  return result;
}
export function completeTask(db: GTDDatabase, id: string, day?: string, now = new Date()): GTDDatabase {
  const task = lookup(db, id);
  if (day !== undefined && (!isDayKey(day) || day > dayKey(now))) throw new Error('Only today or a past daily occurrence can be completed');
  if (task.status === 'done' || task.status === 'cancelled') return db;
  if (supportsDailyRecurrence(task)) {
    const token = day ?? dayKey(now);
    if (task.completedInstances.includes(token)) return db;
    if (task.skippedInstances.includes(token)) throw new Error('This occurrence was skipped');
    if (task.plannedStart && token < dateDay(task.plannedStart)) throw new Error('This occurrence is before the recurrence starts');
    return updateTask(db, id, { completedInstances: [...task.completedInstances, token] }, now);
  }
  if (task.recurrence.trim()) throw new Error('Completing this recurrence is not supported. Its rule has been preserved.');
  if (day && day !== dayKey(now)) throw new Error('Historical nonrecurring tasks cannot be backdated');
  return updateTask(db, id, { status: 'done' }, now);
}
export function moveTask(db: GTDDatabase, id: string, targetID: string, placement: 'before' | 'after' | 'inside'): GTDDatabase {
  const source = lookup(db, id), target = lookup(db, targetID);
  if (!['before', 'after', 'inside'].includes(placement)) throw new Error('Invalid placement');
  if (!sameID(source.workspaceID, target.workspaceID)) throw new Error('Dragging between workspaces is not supported');
  const subtree = subtreeIDs(db, id); if (subtree.has(idKey(targetID))) throw new Error('A task cannot be moved relative to itself or its descendants');
  const parentID = placement === 'inside' ? target.id : target.parentID, now = instant();
  const siblings = sorted(db.tasks.filter(t => !subtree.has(idKey(t.id)) && sameID(t.workspaceID, target.workspaceID) && sameID(t.projectID, target.projectID) && sameID(t.parentID, parentID)));
  const targetIndex = siblings.findIndex(t => sameID(t.id, targetID));
  const at = placement === 'inside' ? siblings.length : targetIndex + (placement === 'after' ? 1 : 0);
  siblings.splice(at, 0, source); const orders = new Map(siblings.map((t, i) => [idKey(t.id), i]));
  const tasks = db.tasks.map(t => {
    if (sameID(t.id, id)) return { ...t, parentID, projectID: target.projectID, sectionID: target.sectionID, order: orders.get(idKey(t.id))!, updatedAt: now };
    if (subtree.has(idKey(t.id))) return { ...t, projectID: target.projectID, sectionID: target.sectionID, updatedAt: now };
    if (orders.has(idKey(t.id))) return { ...t, order: orders.get(idKey(t.id))! };
    return t;
  });
  return checked({ ...db, tasks });
}
export function timerSeconds(timer: ActiveTimer, now = new Date()): number {
  instant(now); const elapsed = timer.pausedAt ? 0 : Math.max(0, (now.getTime() - Date.parse(timer.startedAt)) / 1000);
  return Math.max(0, timer.accumulatedSeconds + elapsed);
}
export interface StartTimerInput { workspaceID: string; taskID?: string | null; mode: TimerMode; targetMinutes?: number; title?: string }
/** Target normalization matches the original: nearest whole minute, 1–180. */
export function normalizePomodoroMinutes(minutes: number): number {
  if (!Number.isFinite(minutes)) throw new Error('Pomodoro target must be a finite number');
  return Math.min(180, Math.max(1, Math.round(minutes)));
}
export function startTimerSession(db: GTDDatabase, input: StartTimerInput, now = new Date()): GTDDatabase {
  if (db.activeTimer) throw new Error('Stop the current timer before starting another');
  if (input.mode !== 'stopwatch' && input.mode !== 'pomodoro') throw new Error('Invalid timer mode');
  const workspace = db.workspaces.find(w => sameID(w.id, input.workspaceID));
  if (!workspace) throw new Error('Workspace was not found');
  const task = input.taskID == null ? undefined : lookup(db, input.taskID);
  if (task && !sameID(task.workspaceID, workspace.id)) throw new Error('Task belongs to another workspace');
  if (task && (task.status === 'done' || task.status === 'cancelled')) throw new Error('Reopen this task before starting a timer');
  const timestamp = instant(now), mode = input.mode;
  return checked({ ...db, activeTimer: { mode, workspaceID: workspace.id, taskID: task?.id ?? null,
    title: task?.title ?? (input.title?.trim() || '无任务专注'), sessionStartedAt: timestamp, startedAt: timestamp,
    pausedAt: null, accumulatedSeconds: 0, targetSeconds: mode === 'pomodoro' ? normalizePomodoroMinutes(input.targetMinutes ?? 25) * 60 : null,
    phase: mode === 'pomodoro' ? 'focus' : null, focusCount: 0 } });
}
/** Legacy callers retain their default 25-minute target and task association. */
export function startTimer(db: GTDDatabase, taskID: string, mode: TimerMode, now = new Date()): GTDDatabase {
  const task = lookup(db, taskID);
  return startTimerSession(db, { workspaceID: task.workspaceID, taskID, mode }, now);
}
export function pomodoroClockState(targetSeconds: number, elapsed: number): { phase: 'remaining' | 'overtime'; seconds: number } {
  if (!Number.isFinite(targetSeconds) || !Number.isFinite(elapsed) || targetSeconds < 0 || elapsed < 0) throw new Error('Invalid timer duration');
  return elapsed < targetSeconds ? { phase: 'remaining', seconds: targetSeconds - elapsed } : { phase: 'overtime', seconds: elapsed - targetSeconds };
}
export function pauseTimer(db: GTDDatabase, now = new Date()): GTDDatabase {
  const timer = db.activeTimer; if (!timer || timer.pausedAt) return db;
  const pausedAt = instant(new Date(Math.max(now.getTime(), Date.parse(timer.startedAt))));
  return checked({ ...db, activeTimer: { ...timer, pausedAt, accumulatedSeconds: timerSeconds(timer, now) } });
}
export function resumeTimer(db: GTDDatabase, now = new Date()): GTDDatabase {
  const timer = db.activeTimer; if (!timer || !timer.pausedAt) return db;
  const startedAt = instant(new Date(Math.max(now.getTime(), Date.parse(timer.pausedAt))));
  return checked({ ...db, activeTimer: { ...timer, startedAt, pausedAt: null } });
}
export function stopTimer(db: GTDDatabase, now = new Date()): GTDDatabase {
  const timer = db.activeTimer; if (!timer) return db;
  const workspaceID = timer.workspaceID ?? (timer.taskID ? lookup(db, timer.taskID).workspaceID : db.workspaces[0]?.id);
  if (!workspaceID) throw new Error('Timer has no workspace; cannot safely record it');
  const endedAt = instant(new Date(Math.max(Date.parse(timer.sessionStartedAt), Date.parse(timer.pausedAt ?? instant(now)))));
  return checked({ ...db, activeTimer: null, timeEntries: [...db.timeEntries, { id: uuid(), workspaceID, taskID: timer.taskID, title: timer.title, startedAt: timer.sessionStartedAt, endedAt, source: timer.mode, pomodoroPhase: timer.phase, note: '', activeSeconds: timerSeconds(timer, now) }] });
}
/** Like the Swift command, duplicates only this task, not its descendants. */
export function duplicateTask(db: GTDDatabase, id: string): GTDDatabase {
  const source = lookup(db, id), now = instant();
  const copy: GTDTask = { ...source, id: uuid(), title: `${source.title} (copy)`, status: 'open', completedAt: null,
    completedInstances: [], skippedInstances: [], createdAt: now, updatedAt: now,
    executionSlots: source.executionSlots.map(slot => ({ ...slot, id: uuid() })) };
  return moveTask({ ...db, tasks: [...db.tasks, copy] }, copy.id, source.id, 'after');
}
export function trashTask(db: GTDDatabase, id: string): GTDDatabase {
  const root = lookup(db, id), ids = subtreeIDs(db, id);
  if (db.activeTimer?.taskID && ids.has(idKey(db.activeTimer.taskID))) throw new Error('Stop this task’s active timer before moving it to Trash');
  const tasks = db.tasks.filter(t => ids.has(idKey(t.id))), timeEntries = db.timeEntries.filter(e => e.taskID && ids.has(idKey(e.taskID)));
  const item: TrashItem = { id: uuid(), kind: 'task', objectID: root.id, workspaceID: root.workspaceID, name: root.title, deletedAt: instant(), projectCategories: [], projects: [], tasks, timeEntries };
  return checked({ ...db, tasks: db.tasks.filter(t => !ids.has(idKey(t.id))), timeEntries: db.timeEntries.filter(e => !e.taskID || !ids.has(idKey(e.taskID))), trashItems: [...db.trashItems, item] });
}
export function restoreTrash(db: GTDDatabase, trashID: string): GTDDatabase {
  const item = db.trashItems.find(t => sameID(t.id, trashID)); if (!item) throw new Error('Trash item was not found');
  const append = <T extends { id: string }>(live: T[], stored: T[]) => { if (stored.some(s => live.some(l => sameID(l.id, s.id)))) throw new Error('Restore would overwrite an existing ID. No data was changed.'); return [...live, ...stored]; };
  const projects = [...item.projects, ...(item.project && !item.projects.some(p => sameID(p.id, item.project?.id)) ? [item.project] : [])];
  const result = { ...db,
    workspaces: append(db.workspaces, item.workspace ? [item.workspace] : []), projects: append(db.projects, projects),
    projectCategories: append(db.projectCategories, item.projectCategories), projectSections: append(db.projectSections, item.projectSections ?? []),
    tagCategories: append(db.tagCategories, item.tagCategories ?? []), tagDefinitions: append(db.tagDefinitions, item.tagDefinitions ?? []),
    tasks: append(db.tasks, item.tasks), timeEntries: append(db.timeEntries, item.timeEntries),
    workspaceOrder: item.workspace ? [...db.workspaceOrder, item.workspace.id] : db.workspaceOrder,
    trashItems: db.trashItems.filter(t => !sameID(t.id, trashID))
  };
  try { return checked(result); } catch (error) { throw new Error(`Cannot restore safely. Restore the original workspace, project or parent first. ${error instanceof Error ? error.message : ''}`); }
}
