/** Synthetic Today acceptance fixture. Never reads or replaces a user database.
 * Usage: TZ=UTC node --import tsx scripts/create-today-qa.ts /tmp/today-qa.json */
import { writeFile } from 'node:fs/promises';
import { createTask, createWorkspace, dayKey, emptyDatabase, exportDatabase, localDate, updateTask, type GTDTask } from '../src/domain/index.js';

const output = process.argv[2];
if (!output) throw new Error('Provide a new output JSON path; an existing file will not be overwritten');
const today = dayKey(new Date());
function at(dayOffset: number, hour = 0, minute = 0) {
  const date = localDate(today);
  date.setDate(date.getDate() + dayOffset);
  date.setHours(hour, minute, 0, 0);
  return date.toISOString();
}
let database = emptyDatabase();
database.workspaces[0].name = 'Today QA';
database = createWorkspace(database, 'Isolation QA');
const [workspaceID, otherWorkspaceID] = database.workspaces.map(workspace => workspace.id);
function task(title: string, patch: Partial<GTDTask>) {
  database = createTask(database, { title, workspaceID });
  const id = database.tasks.at(-1)!.id;
  database = updateTask(database, id, { status: 'open', ...patch });
  return id;
}
const plannedTaskID = task('Morning plan 09:00', { plannedStart: at(0, 9), plannedEnd: at(0, 9, 45), plannedPrecision: 'minute' });
task('Daily wall-clock 08:30', { plannedStart: at(-1, 8, 30), plannedEnd: at(-1, 9), plannedPrecision: 'minute', recurrence: 'RRULE:FREQ=DAILY' });
task('Ready to schedule', { plannedStart: today, plannedPrecision: 'date' });
task('Cross-day progress', { plannedStart: dayKey(new Date(at(-1))), plannedEnd: dayKey(new Date(at(1))), plannedPrecision: 'date', planRangeIntent: 'progress' });
task('Complete within range', { plannedStart: dayKey(new Date(at(-1))), plannedEnd: dayKey(new Date(at(1))), plannedPrecision: 'date', planRangeIntent: 'complete-within' });
task('Overdue backlog', { deadline: at(-1, 17), deadlinePrecision: 'minute' });
task('Untimed point 10:00', { plannedStart: at(0, 10), plannedPrecision: 'minute' });
database.timeEntries = [{
  id: crypto.randomUUID(), workspaceID, taskID: plannedTaskID, title: 'Past actual focus',
  startedAt: at(-1, 23, 30), endedAt: at(0, 0, 30), source: 'stopwatch', activeSeconds: 1800, note: 'Synthetic paused cross-midnight session',
}, {
  id: crypto.randomUUID(), workspaceID: otherWorkspaceID, title: 'Other workspace record',
  startedAt: at(-1, 20), endedAt: at(-1, 21), source: 'manual', note: 'Must not appear in Today QA',
}];
await writeFile(output, exportDatabase(database), { flag: 'wx', mode: 0o600 });
console.log(`Created fictional Today fixture for local date ${today}: ${output}`);
