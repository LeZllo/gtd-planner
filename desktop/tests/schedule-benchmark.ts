/** Synthetic CPU-only regression probe; not an animation/frame-rate benchmark. */
import { createTask, emptyDatabase, updateTask } from '../src/domain/index.js';
const output = [];
for (const size of [200, 500, 1000, 2000]) {
  let db = emptyDatabase();
  db = createTask(db, { workspaceID: db.workspaces[0].id, title: 'Synthetic slot benchmark' });
  db.tasks[0].executionSlots = Array.from({ length: size }, (_, index) => ({ id: crypto.randomUUID(), start: new Date(Date.UTC(2026, 0, 1 + index, 9)).toISOString(), end: new Date(Date.UTC(2026, 0, 1 + index, 10)).toISOString() }));
  const samples = [];
  for (let run = 0; run < 6; run++) {
    const start = performance.now(); updateTask(db, db.tasks[0].id, { title: 'Changed title' });
    if (run) samples.push(performance.now() - start);
  }
  samples.sort((a, b) => a - b);
  output.push({ slots: size, medianTitleEditMs: Number(samples[2].toFixed(2)) });
}
console.log(JSON.stringify(output, null, 2));
