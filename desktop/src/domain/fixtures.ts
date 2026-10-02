import type { GTDDatabase, GTDTask } from './types.js';
import { createTask, emptyDatabase } from './operations.js';
import { dayKey } from './dates.js';
import { validateDatabase } from './validation.js';

/** Synthetic records only. Date offsets follow the local calendar, including DST. */
export function demoDatabase(now = new Date()): GTDDatabase {
  const id = (n: number) => `00000000-0000-4000-8000-${String(n).padStart(12, '0')}`;
  const at = (offset: number, hour = 0, minute = 0) => { const d = new Date(now); d.setDate(d.getDate() + offset); d.setHours(hour, minute, 0, 0); return d.toISOString(); };
  const civil = (offset: number) => { const d = new Date(now); d.setDate(d.getDate() + offset); return dayKey(d); };
  let db = emptyDatabase();
  db.workspaces = [{ id: id(1), name: 'Work', symbolName: 'briefcase', colorHex: '#2563EB' }, { id: id(2), name: 'Life', symbolName: 'house', colorHex: '#08916E' }];
  db.workspaceOrder = [id(1), id(2)]; db.pinnedWorkspaceIDs = [id(1)];
  db.projects = [{ id: id(10), workspaceID: id(1), name: 'Product launch', category: 'Projects', colorHex: '#2563EB', symbolName: 'paperplane', order: 0, note: 'A fictional launch plan for exploring the prototype.' }, { id: id(11), workspaceID: id(1), name: 'Team operations', category: 'Projects', colorHex: '#8B5CF6', symbolName: 'person.2', order: 1 }, { id: id(12), workspaceID: id(2), name: 'A little more outdoors', category: 'Personal', colorHex: '#08916E', symbolName: 'leaf', order: 0 }];
  db.projectCategories = [{ id: id(20), workspaceID: id(1), name: 'Projects', colorHex: '#2563EB', order: 0 }, { id: id(21), workspaceID: id(2), name: 'Personal', colorHex: '#08916E', order: 0 }];
  db.projectSections = [{ id: id(30), projectID: id(10), name: 'This week', colorHex: '#2563EB', order: 0 }];
  const add = (n: number, title: string, patch: Partial<GTDTask> = {}) => {
    db = createTask(db, { title, workspaceID: id(1) });
    db.tasks[db.tasks.length - 1] = { ...db.tasks.at(-1)!, id: id(n), status: 'open', projectID: id(10), sectionID: id(30), order: n, createdAt: at(-5, 9), updatedAt: at(-1, 10), ...patch };
  };
  add(100, 'Prepare the launch story', { priority: 'high', plannedStart: civil(-1), plannedEnd: civil(2), plannedPrecision: 'date', deadline: civil(2), deadlinePrecision: 'date', tags: ['Launch'], note: 'Start with the customer problem. Keep the narrative focused and concrete.\n\nThis demo is entirely synthetic.' });
  add(101, 'Outline the release announcement', { parentID: id(100), priority: 'high', plannedStart: at(0, 9), plannedEnd: at(0, 10), plannedPrecision: 'minute', executionSlots: [{ id: id(300), start: at(0, 9), end: at(0, 10) }], tags: ['Writing'] });
  add(102, 'Choose three customer benefits', { parentID: id(101), priority: 'medium', plannedStart: civil(0), plannedPrecision: 'date' });
  add(103, 'Review screenshots and captions', { parentID: id(100), plannedStart: civil(1), plannedPrecision: 'date', priority: 'medium', tags: ['Design'] });
  add(104, 'Check the signup journey', { priority: 'high', deadline: civil(0), deadlinePrecision: 'date', executionSlots: [{ id: id(301), start: at(0, 13, 30), end: at(0, 14, 15) }], note: 'Walk through the first-run experience with a fresh local demo account.' });
  add(105, 'Send the weekly project update', { projectID: id(11), sectionID: null, plannedStart: civil(1), plannedPrecision: 'date', priority: 'medium', tags: ['Communication'] });
  add(106, 'Ten-minute daily review', { projectID: id(11), sectionID: null, recurrence: 'RRULE:FREQ=DAILY', plannedStart: at(-3, 16), plannedEnd: at(-3, 16, 10), plannedPrecision: 'minute', completedInstances: [civil(-1)], skippedInstances: [civil(-2)], tags: ['Routine'] });
  add(107, 'Collect feedback on the draft', { status: 'waiting', actionList: 'waiting', deadline: civil(3), deadlinePrecision: 'date', tags: ['Launch'] });
  add(108, 'Explore an onboarding checklist', { status: 'someday', actionList: 'someday-maybe', projectID: null, sectionID: null, note: 'An idea for later, with no implied schedule.' });
  add(109, 'Organize the research notes', { status: 'done', completedAt: at(0, 8, 30), tags: ['Research'] });
  add(110, 'Capture a new idea', { status: 'inbox', projectID: null, sectionID: null });
  add(111, 'Plan a weekend walk', { workspaceID: id(2), projectID: id(12), sectionID: null, plannedStart: civil(2), plannedPrecision: 'date', priority: 'low', tags: ['Outdoors'] });
  db.timeEntries = [{ id: id(400), workspaceID: id(1), taskID: id(109), title: 'Organize the research notes', startedAt: at(0, 8), endedAt: at(0, 8, 30), source: 'pomodoro', pomodoroPhase: 'focus', note: 'Synthetic demo focus record', activeSeconds: 25 * 60 }, { id: id(401), workspaceID: id(1), taskID: id(100), title: 'Prepare the launch story', startedAt: at(-1, 14), endedAt: at(-1, 14, 45), source: 'stopwatch', note: '', activeSeconds: 40 * 60 }];
  db.tagCategories = [{ id: id(500), workspaceID: id(1), name: 'Focus areas', colorHex: '#2563EB', order: 0, createdAt: at(-5), updatedAt: at(-1) }];
  db.tagDefinitions = ['Launch', 'Writing', 'Design', 'Communication', 'Routine', 'Research'].map((name, i) => ({ id: id(510 + i), workspaceID: id(1), categoryID: id(500), name, colorHex: '#2563EB', note: '', order: i, createdAt: at(-5), updatedAt: at(-1) }));
  db.activityLog = [{ id: id(600), timestamp: now.toISOString(), action: 'demo-created', target: 'Synthetic demo', detail: 'No real user data is included.' }];
  return validateDatabase(db).database;
}
