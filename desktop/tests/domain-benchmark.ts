/** Synthetic CPU benchmark, not a UI frame-rate or Swift parity claim.
 * Run: node --import tsx tests/domain-benchmark.ts
 */
import { performance } from 'node:perf_hooks';
import { createTask, emptyDatabase, moveTask, parseImport, taskTree, tasksForDay, todayScheduleSnapshot, updateTask, type GTDDatabase } from '../src/domain/index.js';
const id = (n: number) => `bbbbbbbb-0000-4000-8000-${String(n).padStart(12, '0')}`;
function fixture(count: number): GTDDatabase {
  const db = emptyDatabase(), template = createTask(db, { title: 'Benchmark', workspaceID: db.workspaces[0].id }).tasks[0];
  db.tasks = Array.from({ length: count }, (_, i) => ({ ...template, id: id(i + 1), title: `Synthetic task ${i + 1}`, parentID: i % 10 ? id(i - i % 10 + 1) : null, plannedStart: '2026-04-12', plannedPrecision: 'date', order: i }));
  return db;
}
function measure(fn: () => unknown) { fn(); const samples = Array.from({ length: 5 }, () => { const start = performance.now(); fn(); return performance.now() - start; }).sort((a, b) => a - b); return Math.round(samples[2] * 100) / 100; }
for (const count of [1000, 10000]) {
  const db = fixture(count), text = JSON.stringify(db), workspace = db.workspaces[0].id;
  const scheduled = { ...db, tasks: db.tasks.map((task, index) => ({ ...task, executionSlots: index % 10 ? [] : [{ id: id(count + index + 1), start: '2026-04-12T09:00:00Z', end: '2026-04-12T09:30:00Z' }] })) };
  console.log(JSON.stringify({ tasks: count, fixture: '1 root + 9 children per group; no trash', millisecondsMedianOf5: {
    tree: measure(() => taskTree(db, workspace)), dayProjection: measure(() => tasksForDay(db, workspace, '2026-04-12')),
    todaySnapshotWithOneSlotPerTenTasks: measure(() => todayScheduleSnapshot(scheduled, workspace, '2026-04-12', new Date('2026-04-12T10:00:00Z'))),
    validatedTitleEdit: measure(() => updateTask(db, id(1), { title: 'Edited root' })), validatedMove: measure(() => moveTask(db, id(1), id(11), 'after')),
    validateImport: measure(() => parseImport(text))
  } }));
}
