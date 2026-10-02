# Prototype domain boundary

These modules are framework-independent TypeScript. The renderer projects them; persistence validates and saves them. Dates and stable IDs stay in JSON rather than becoming class instances.

## Data migration and safety

- Schema versions 1–11 are accepted; newer/invalid schemas and unknown envelope versions are rejected. Export uses `{format:"gtd-planner-electron",version:1,database}`. This envelope is for this prototype, not a claim of direct import back into the Swift app.
- Validation happens in memory before the caller replaces any database. Corrupt UUIDs, duplicate IDs, invalid enum/type/date values, missing or cross-workspace relationships, mismatched project sections, parent cycles, and malformed archive snapshots fail explicitly. No records are deleted to repair a snapshot.
- All supplied known fields, ISO timestamp strings (including offsets/sub-millisecond precision), unknown extension fields and legacy collections are retained. Missing legacy fields receive defaults. Pre-11 entities missing IDs receive new UUIDs with a warning; invalid supplied IDs are never replaced. Missing creation dates use existing updatedAt or a deterministic epoch fallback, with a warning.
- A user-file import rejects any non-null active timer and asks the user to stop/export in the source app. The separate `parseStoredDatabase` boundary accepts a validated active timer solely for reopening the app’s own durable state. Source and destination timer protection also belongs in the import UI.
- Trash retains selected task plus descendants and associated time entries. It never permanently deletes them. Restoration refuses ID collisions and missing required ancestors/projects/workspaces. Separate child/parent trash snapshots remain valid, with parent-first restoration.

## Dates and recurrence

- `dayKey` uses the current device’s local calendar, not `toISOString().slice(0,10)`.
- New date-only values are ISO civil dates `YYYY-MM-DD`. They remain the same civil day across timezones. Minute-precise values and legacy exported dates are offset-bearing ISO instants and retain the original string.
- Legacy Swift date-only fields were exported as instants without an originating timezone. That timezone cannot be reconstructed. Their projected day therefore follows the current device timezone, matching Swift’s `Calendar.current`; import explicitly warns. Nothing silently shifts/re-encodes stored timestamps.
- Civil planned ranges include the final selected day. Minute ranges and execution slots are half-open `[start,end)` so midnight belongs to the next day only when there is positive overlap. Day boundaries use local next-midnight construction, including daylight-saving transitions.
- Only plain `FREQ=DAILY` (optional `RRULE:` prefix and `INTERVAL=1`) is expanded. Other recurrence expressions are retained with an import warning, not interpreted as plain daily. The Swift baseline is also DAILY-aware, not a full RRULE engine; its broader DAILY-token detection still needs comparison with this stricter boundary. Full RRULE support is not required migration parity. Daily completion adds a day token idempotently without completing the series. Skipped occurrences are hidden; completed daily instances remain visible on their date. No future completion is allowed.
- Nonrecurring completed tasks appear on their completion date. Overdue deadline backlog appears only on the actual current day, never every browsed calendar day. Undated inbox work is not silently scheduled.

## Mutation and timer behavior

- Every public mutation returns a new database and does not mutate the input. Finite user operations validate their resulting graph. Do not call mutations on drag pointer samples or timer ticks.
- Stable sorting keeps original array order for ties. Parent-before-child traversal and descendant collection are iterative and avoid recursive stack overflow. Moves reject cycles and cross-workspace changes; a cross-project move carries the subtree.
- Nonrecurring parent completion cascades down. Reopening a completed branch reopens its subtree and completed ancestors. Single-item duplication follows the Swift command and deliberately does not duplicate descendants.
- Timer elapsed time is derived, never persisted per tick. Pause/resume retain the first session start and accumulate only running segments. Stop creates one immutable log, is idempotent once stopped, and uses the pause time when stopped while paused. Clock rollback never erases already accumulated time.
- Pomodoro defaults to 25 minutes. Reaching the target does not auto-complete; overtime continues until explicit stop, matching the Swift behavior. The Swift baseline has no automatic focus/break cycle to port. Remaining timer parity includes configurable 1–180-minute targets and the saved default, optional no-task sessions, and a visible overtime counter; elapsed overtime is already retained even though the prototype countdown display stops at zero.

## Verification scope

Run `node --import tsx --test tests/domain.test.ts` for targeted tests. They cover import corruption, unknown schemas/extensions, UUIDs/relationships/cycles, local civil dates, DST, recurrence, completion idempotence/cascades, tree moves, timers, duplication and recoverable trash. These are not full parity with the original 189 Swift tests.

`node --import tsx tests/domain-benchmark.ts` is a reproducible synthetic CPU benchmark at 1k/10k tasks, reporting median-of-five timings after warmup. It excludes trash and does not measure rendered UI frame rate. Full-validation mutation and archive-heavy workloads need optimization before large-data performance parity can be claimed.

Deferred parity includes Swift timeline wall-clock template rendering, focus record editing, full category/label management, and all original planner horizon/quadrant policy nuance. Existing data for these features is preserved, not claimed to be fully editable here. The Swift Filters entry is already a placeholder; custom filter authoring is not part of required parity.
