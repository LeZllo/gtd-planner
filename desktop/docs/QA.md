# QA record

Date: 2026-10-02. All records are synthetic and use a dedicated preview data directory. No personal SwiftData database or real backup was opened.

## Automated checks executed

- 31 domain cases: model validation, UUID/reference/cycle safety, unknown extension preservation, legacy defaults and schema rejection, JSON roundtrip, local civil-day and DST boundaries, daily completion/skipping, tree moves, duplicate semantics, timer pause/resume/stop, recoverable trash, deep hierarchies
- 9 desktop storage cases: empty first launch, serialized newest-wins writes, invalid-write refusal, corrupt-primary recovery, unrecoverable-data refusal, active-timer reopen, missing-primary backup recovery
- 2 browser-adapter cases: corrupt-primary backup preservation and missing-primary recovery
- 6 actual-focus projection regressions: workspace identity, half-open midnight, paused cross-day proration, zero/null active seconds, local timezone and DST
- 29 Today domain cases: dual-lane projections, daily wall-clock/DST behavior, plan snapping/guards, actual-record safety, optional timers and current date-scope membership
- 11 renderer-helper cases: sub-minute/DST draft fidelity, raw no-op preservation, timer day clipping, UUID compatibility, deadline race and stale candidate selection
- 2 CSS consistency cases: shared blue completion controls, unchanged green actual-record classification
- Current total: 90 tests passed
- Renderer and Electron TypeScript checks plus full production Vite build passed
- npm audit after updating packaging dependencies: 0 reported vulnerabilities (this is not a guarantee of absence of vulnerabilities)

## Bugs found and fixed during review

- A missing primary file previously returned blank onboarding despite a valid backup. Both sources are now inspected first
- Backups and exports now stage bytes and use same-directory atomic rename rather than truncating an existing file
- Browser adapter no longer overwrites a corrupt primary or replaces a good backup with corrupt bytes
- Electron close uses a save acknowledgement, safe startup/crash fallback, and correlated attempts; renderer callback integration and native immediate-close behavior verified

## Performance evidence

`node --import tsx tests/domain-benchmark.ts` creates synthetic 1,000 / 10,000 task datasets and reports median-of-five projection and mutation times. It measures domain operations on this cloud execution environment, not actual frame rate, input latency, memory on a user device or full UI responsiveness. Initial 10k observations: tree about 16 ms; day projection about 19 ms; validated edit/move about 110 ms. Full validation on each committed mutation is still material at 10k and must never run on pointer samples. Archive-heavy datasets are not included.

## Native and platform checks

- Official Electron binary and compiled production app ran on the native cloud Linux desktop with sandbox enabled
- Native cloud desktop launched both the compiled application and packaged Linux binary; sandbox remained enabled
- Cloud browser localhost navigation is blocked by its client; browser UI acceptance has not been claimed
- macOS and Windows build, installers, signing/notarization, keyboard conventions, DPI and assistive technology remain unverified
- Existing 189 Swift tests have not been ported in full and are not counted as Electron passes

## Native interaction checks executed

- Empty first launch displayed; explicitly loaded 12 synthetic tasks across 2 workspaces, verified durable file and 0600 permissions
- Selected parent task and inspected fields; started stopwatch, paused after 24.745 seconds, closed and reopened app, observed exact paused time retained
- Resumed timer, navigated month calendar, stopped; actual record retained 36.903 active seconds across 179.083 wall-clock seconds, excluding the pause
- Selected October 2 and verified four projected tasks in its daily list
- Added an Inbox task through keyboard input, edited title without blurring, immediately closed the window; close handshake saved the edited title correctly
- Linux unpacked package created and archive listing verified to exclude synthetic QA storage, logs and artifacts
- Original-column layout correction completed and visually checked against Swift source/repository reference: source rail, conditional project/tag pane, task center, right inspector. Native screenshot saved and inspected

## Final native migration/interaction checks

- Task-handle drag changed Review screenshots into a child of Check signup; dragging a parent into its descendant was rejected without changing the persisted tree
- Legacy JSON containing 1,000 synthetic tasks showed counts before replacement. Cancel left the data file SHA-256 unchanged
- Explicit confirmation persisted 1,000 tasks; the previous-version backup retained all 13 pre-import tasks including the latest unblurred title edit
- Windowed 1,000-task list scrolled to later rows and selection opened the correct inspector
- Tomorrow displayed the expected 1,000 scheduled tasks with the original planning layout; Calendar showed 1,000 on the correct day and its selected-day list rendered and scrolled
- CUA interaction observations are not measured frame-rate guarantees. Full 10k GUI stress, archive-heavy performance and accessibility-tree behavior remain unverified; this environment exposed only X11 window metadata even with accessibility enabled

- Final safety gate: data replacement has a separate IPC method and permanent timestamped `Backups/before-import-*` snapshot; ordinary later saves cannot rotate it away. Tests verify snapshot retention and active-timer refusal before replacement.
- Final packaged-binary check: import-specific IPC completed on the native desktop and created a separate timestamped pre-import file containing all 1,000 prior tasks; current data also validated at 1,000 tasks afterward


## Actual-focus statistics hotfix after first published preview

Base: `41bd3ace7f644f6ecbbe97d952a41ac709ac211b`. Corrected the overview to count only the selected workspace and the selected local day's overlap. Timers with stored active seconds are prorated across their full wall-clock span, as in the Swift baseline; the UI explains that cross-day pause attribution is estimated. The original entries are not rewritten.

- All 48 tests and the production build passed
- Real compiled Electron window on cloud Linux, sandbox enabled, isolated synthetic database and process timezone UTC: Work A shows 30 minutes on October 2 and 15 minutes on October 1 for a 45-active-minute session crossing midnight; Work B shows only its own 90 minutes on October 2
- Verified the Today page after switching workspaces and the Calendar overview after selecting the previous day; no aggregate from the other workspace leaked into either total
- Scope documentation corrected: Filters were already a Swift placeholder; automatic Pomodoro break cycles and a full RRULE engine are not baseline parity requirements


## Today phase A implementation checks

Base: published statistics fix `c8f97585d817aaf1f1ea4605122c1a7864f74635`. The renderer keeps the source rail, conditional second navigation pane, top toolbar and right inspector roles. The new 00–24 dual-lane view is limited to Today; Tomorrow and Calendar do not yet use it.

Automated and code review:
- 90 aggregate tests passed, including 29 Today domain, 11 renderer-helper and 2 CSS consistency regressions; production renderer/Electron build and diff checks passed
- Fixed current-day membership checks so stale/undated rows cannot be completed through a dated action; ordinary project/inbox completion remains available
- Actual metadata-only edits preserve sub-minute, timezone-offset and repeated-hour timestamps, absent fields and active seconds. Failed mutations leave their editor open
- Pointer movement is contained in a small local preview component with refs/RAF; commits use existing validated persistence. Timer ticks are in a separate overlay; projections invalidate on database, workspace, day and deadline changes. Project-name and task-plan-block indexes are memoized, avoiding a full scan for each Today row/task-picker item
- Synthetic median-of-five Today snapshot CPU observations were about 6–7 ms for 1k tasks/100 slots and 54–60 ms for 10k tasks/1k slots on this cloud environment. These are not GUI latency/FPS measurements

Native checks actually executed on the initial integrated build:
- Opened the real sandbox-enabled Electron window using the fictional Today fixture. Verified default 08:00 scroll, planned/actual lanes, 75 planned minutes and 15 estimated actual minutes
- Dragged 11:00–11:45 in the planned lane. Cancel left the database SHA-256 unchanged; confirming on a second attempt persisted one exact execution slot and preserved the task's original plan/deadline
- Scrolled to midnight and saw the clipped 00:00–00:30 portion of the original cross-midnight actual record
- Dragged 03:00–03:30 in the actual lane and saved a manual record. The total changed from 15 to 45 minutes; disk inspection verified 1,800 seconds and no changes to any task plan/deadline
- Cancelled another unsubmitted draft and closed the app normally; disk contained the committed plan/actual records and no active timer

Additional native checks on the packaged reviewed build:
- Reopened and verified the previously committed execution slot and manual actual record
- Overlapping 02:45–03:15 actual backfill was rejected in Chinese while the existing 03:00–03:30 record stayed intact and the draft remained open
- A future 12:00–12:15 selection defaulted to immediate Pomodoro; switching to manual and saving was rejected while retaining the draft
- A precise deadline at 07:25:32.297 UTC changed both Today summary and right-hand overdue counts from 1 to 2 while a draft remained open, with no navigation or database commit
- Started a one-minute no-task Pomodoro, observed overtime, paused at 108.861 active seconds, closed/reopened and observed the same +48-second overtime. Explicit stop created exactly one record ending at the pause timestamp, excluding later paused/closed time
- Edited only the note on a cross-midnight paused-focus record. Disk comparison confirmed original start/end strings and active seconds were unchanged
- Native review found inconsistent rounded/truncated aggregate minute labels. They now share truncation after summing seconds, with a regression test; the final rounding fix was visually rechecked with both totals at 46 minutes

Final native acceptance:
- Switched to the other workspace: Today tasks, planned minutes and actual minutes were all zero; switching back restored the original counts and matching 46-minute labels
- Actual deletion showed an explicit confirmation. Cancel left the data SHA-256 unchanged; confirm removed only the selected synthetic timer record (4 to 3 entries), with task/slot arrays byte-equivalent
- Final completed-state check: marked task 0999 done, opened the completed list and inspector, and visually confirmed both checkboxes use shared blue fill/border with a white check; actual-record green remains unchanged
- The Linux window manager intercepted Alt-drag as a window move. Shift was added as an equivalent 5-minute modifier without changing OS settings. Shift-drag selected exactly 10:05–10:20 in the real app; Escape cancellation left the dataset hash unchanged
- In a separate 1,000-task fixture, searched task 0999 in the picker and saved that exact 10:05–10:20 slot. Disk inspection confirmed 1,000 tasks and exactly one slot. Switched schedule/list modes, scrolled to the last task, repeatedly changed selection, and navigated Calendar→Today successfully

Limits: native actions are functional observations, not measured frame-rate/input-latency guarantees. 10k GUI, archive-heavy and densely overlapping timelines remain unverified. Released-draft Escape/cancel were exercised; raw OS-generated pointercancel/lost-capture paths have code-review coverage but were not separately injected through the desktop tool. macOS/Windows remain untested. See `TODAY-ACCEPTANCE.md` for the checklist.
