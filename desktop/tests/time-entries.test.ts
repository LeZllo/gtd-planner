import test from 'node:test';
import assert from 'node:assert/strict';
import { actualFocusForDay, type TimeEntry } from '../src/domain/index.js';

const workspace = 'aaaaaaaa-0000-4000-8000-000000000001';
function entry(start: string, end: string, patch: Partial<TimeEntry> = {}): TimeEntry {
  return { id: crypto.randomUUID(), workspaceID: workspace, title: 'Synthetic focus', startedAt: start, endedAt: end, source: 'manual', note: '', ...patch };
}
function inZone(zone: string, run: () => void) {
  const previous = process.env.TZ;
  process.env.TZ = zone;
  try { run(); } finally { if (previous === undefined) delete process.env.TZ; else process.env.TZ = previous; }
}

test('actual focus is isolated to the chosen workspace with case-insensitive UUIDs', () => inZone('UTC', () => {
  const entries = [entry('2026-10-01T10:00:00Z', '2026-10-01T11:00:00Z'), entry('2026-10-01T10:00:00Z', '2026-10-01T12:00:00Z', { workspaceID: 'bbbbbbbb-0000-4000-8000-000000000002' })];
  assert.deepEqual(actualFocusForDay(entries, workspace.toUpperCase(), '2026-10-01'), { seconds: 3600, estimated: false });
  assert.equal(actualFocusForDay(entries, 'cccccccc-0000-4000-8000-000000000003', '2026-10-01').seconds, 0);
}));

test('manual cross-midnight records are clipped to each half-open local day without mutation', () => inZone('UTC', () => {
  const entries = [entry('2026-10-01T23:30:00Z', '2026-10-02T00:30:00Z')];
  const before = JSON.stringify(entries);
  for (const day of ['2026-10-01', '2026-10-02']) assert.deepEqual(actualFocusForDay(entries, workspace, day), { seconds: 1800, estimated: false });
  assert.equal(actualFocusForDay(entries, workspace, '2026-10-03').seconds, 0);
  assert.equal(JSON.stringify(entries), before);
  assert.equal(actualFocusForDay([entry('2026-10-01T23:00:00Z', '2026-10-02T00:00:00Z')], workspace, '2026-10-02').seconds, 0);
}));

test('paused cross-day timers prorate active seconds and conserve the session total', () => inZone('UTC', () => {
  const entries = [entry('2026-10-01T23:30:00Z', '2026-10-02T01:00:00Z', { source: 'stopwatch', activeSeconds: 2700 })];
  const first = actualFocusForDay(entries, workspace, '2026-10-01');
  const second = actualFocusForDay(entries, workspace, '2026-10-02');
  assert.deepEqual(first, { seconds: 900, estimated: true });
  assert.deepEqual(second, { seconds: 1800, estimated: true });
  assert.equal(first.seconds + second.seconds, entries[0].activeSeconds);
}));

test('same-day active seconds exclude pauses; zero and null remain distinct', () => inZone('UTC', () => {
  const make = (activeSeconds: number | null) => [entry('2026-10-01T10:00:00Z', '2026-10-01T11:00:00Z', { source: 'stopwatch', activeSeconds })];
  assert.deepEqual(actualFocusForDay(make(1200), workspace, '2026-10-01'), { seconds: 1200, estimated: false });
  assert.equal(actualFocusForDay(make(0), workspace, '2026-10-01').seconds, 0);
  assert.equal(actualFocusForDay(make(null), workspace, '2026-10-01').seconds, 3600);
  assert.deepEqual(actualFocusForDay([entry('2026-10-01T10:00:00Z', '2026-10-01T10:00:00Z', { activeSeconds: 0 })], workspace, '2026-10-01'), { seconds: 0, estimated: false });
}));

test('cross-midnight clipping follows local date instead of UTC timestamp prefix', () => inZone('America/Los_Angeles', () => {
  const entries = [entry('2026-10-02T06:30:00Z', '2026-10-02T07:30:00Z')];
  assert.equal(actualFocusForDay(entries, workspace, '2026-10-01').seconds, 1800);
  assert.equal(actualFocusForDay(entries, workspace, '2026-10-02').seconds, 1800);
}));

test('DST short and long days use actual local-midnight intervals and preserve prorated totals', () => inZone('America/New_York', () => {
  for (const [day, start, end, hours] of [
    ['2026-03-08', '2026-03-08T05:00:00Z', '2026-03-09T04:00:00Z', 23],
    ['2026-11-01', '2026-11-01T04:00:00Z', '2026-11-02T05:00:00Z', 25],
  ] as const) {
    assert.equal(actualFocusForDay([entry(start, end)], workspace, day).seconds, hours * 3600);
    assert.deepEqual(actualFocusForDay([entry(start, end, { activeSeconds: 600 })], workspace, day), { seconds: 600, estimated: false });
  }
}));
