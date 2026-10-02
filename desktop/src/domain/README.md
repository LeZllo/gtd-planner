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
- Pomodoro defaults to 25 minutes. Reaching the target does not auto-complete; overtime continues until explicit stop, matching the Swift behavior. The Swift baseline has no automatic focus/break cycle to port. The optional-task `startTimerSession` command supports 1–180-minute targets; legacy `startTimer` stays source-compatible. `pomodoroClockState` derives remaining/overtime without mutation. The renderer owns any saved duration preference.

## Verification scope

Run `node --import tsx --test tests/domain.test.ts` for targeted tests. They cover import corruption, unknown schemas/extensions, UUIDs/relationships/cycles, local civil dates, DST, recurrence, completion idempotence/cascades, tree moves, timers, duplication and recoverable trash. These are not full parity with the original 189 Swift tests.

`node --import tsx tests/domain-benchmark.ts` is a reproducible synthetic CPU benchmark at 1k/10k tasks, reporting median-of-five timings after warmup. It excludes trash and does not measure rendered UI frame rate. Full-validation mutation and archive-heavy workloads need optimization before large-data performance parity can be claimed.

Remaining parity includes full category/label management and all original planner horizon/quadrant policy nuance. Existing data for these features is preserved, not claimed to be fully editable here. The Swift Filters entry is already a placeholder; custom filter authoring is not part of required parity.

## Today schedule contract

- `todayScheduleSnapshot` returns clipped planned and actual blocks for a local civil day; block bounds are ISO strings, durations are seconds. `actualEntries` and each actual block’s `entry` retain the original editable record and its full cross-day range. `actualFocusForDay` and the actual lane share the same clipping/proration helper. Active timers never count as finished actual focus.
- Minute task plans are concrete blocks only when they end no later than the next midnight; longer multi-day intentions stay in the progress/complete-within drawer until explicitly scheduled. Point plans have a cosmetic half-hour footprint but zero planned duration, and overlap warnings use only the point instant.
- Supported plain daily minute templates preserve local wall time, including DST gap normalization (02:30 becomes 03:30) and first repeated time during a fold. A gap-inverted end retains the original elapsed duration. Civil days are 23/24/25 hours as appropriate, while the timeline remains 00–24 wall-clock rows.
- Date-only deadlines expire after their local civil day; minute deadlines use their exact instant. `deadlineInstant` and the optional `tasksForDay`/snapshot `now` arguments let the renderer invalidate at the boundary without polling the full database every second. Overdue comparison is strictly before `now`.
- `makeScheduleSelection` is a pure 15-minute snap preview, or 5-minute with fine snap; it neither validates nor mutates the database. A committed execution slot validates once, guards the selected workspace/finished task/every occupied daily occurrence, and returns the same database for an existing equal-instant slot. Plan overlaps are advisory.
- Actual add/edit/delete commands are workspace-scoped. Added and resized ranges must end by `now` and may not overlap stored actuals or the current running/paused timer span. Half-open adjacent endpoints are allowed. Historical records can be associated with finished tasks.
- Actual edits accept only task/title/note/range patches against current state. Notes and equivalent-instant time formatting preserve original ISO text, active seconds, source, phase, unknown fields and task plans. An explicit range change replaces active seconds with the new duration. Imported future timestamps remain editable only when their actual range is unchanged.
- `setTaskCompletionForDay` takes the desired state, so retries are idempotent. Future completion and historical nonrecurring completion/reopening remain forbidden; daily completion never finishes the series. Dated commands recheck current day membership at commit time, so stale removed/moved plans, unrelated undated tasks and other-day completions cannot be changed through a retained Today row.

`node --import tsx --test tests/today-schedule.test.ts` covers snapshot membership/categories, DST gap/fold, midnight/points, immutable and idempotent commands, workspace/daily guards, actual conflicts and metadata/range edits, optional-task targets/overtime, and date-scoped completion safety.
