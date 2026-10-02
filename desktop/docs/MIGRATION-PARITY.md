# Migration inventory

Source baseline: Swift `39e02786fed76670f484f2e41074cb5680a257bc`. This is a migration inventory, not a claim that all old behavior already passes.

## Layout contract

The original `ModernContentView` owns a fixed 78px source rail. Its groups are Inbox / Projects / Tags / Filters; Today / Tomorrow / Next Seven Days / Quadrants / Calendar; Logs / Trash; Settings / Help at the bottom.

Projects have a separate 300px second pane with workspace chooser, project search, category/project tree, and creation controls at the bottom. Tags substitute their own second-pane browser. Task content follows that pane, with a right-hand inspector. The old Today, upcoming planning and calendar routes do not retain the project browser. Top-level stopwatch, Pomodoro, task/Gantt and creation controls belong to the main top bar. The Electron layout follows this functional placement, with stronger contrast but no new information architecture.

## Function mapping

| Swift source | Reusable specification | Prototype implementation / boundary |
| --- | --- | --- |
| Models.swift | Schema 11 names, UUID relationships, date precision, slots, recurrence instances, timers and archives | TypeScript types and validated JSON boundary preserve these fields; Swift code is not directly reused |
| DomainServices.swift / AppModel+Task | Task tree, status, project/parent moves, anti-cycle checks | Pure domain commands and working list/inspector; targeted cases ported, not all original tests |
| TodayExecutionServices / TodayViews | Today membership and execution semantics; baseline recurrence projection recognizes DAILY, not full RRULE | Working list and plan-slot display; plain daily projection only, with other expressions preserved and warned about; complete 00–24 planned/actual dual lanes, actual-entry editing and drag scheduling remain parity work |
| DayPlanning / PlanningHorizon | Tomorrow and next seven calendar days | Date projections and creation; next-seven means tomorrow through +7, excluding today; full day-group presentation remains parity work |
| QuadrantServices / QuadrantViews | Important/urgent classification | Working priority/deadline-based columns and task selection; not a new recurrence engine |
| CalendarPlanningServices / Views | Month grid and selected-day operations | Working calendar/day selection and inspection; all historical/future completion rules still need full specification port |
| AppModel+Timer / TimeEntry | Stopwatch, pause/resume, active seconds and records; Pomodoro overtime until manual stop, without automatic break cycling | Native start/pause/reopen/resume/stop verified; configurable 1–180-minute targets and saved default, optional no-task sessions and visible overtime remain parity work |
| AppModel+Selection | Filters navigation entry is a placeholder in the Swift baseline | Placeholder entry retained; custom filter authoring is not required migration parity |
| LocalDatabase / AppModel+Persistence | JSON export, guarded replacement and backups | Dedicated versioned local file, safe import preview, explicit confirmation and atomic writes; no direct SwiftData reuse |
| AppModel+Archive / Tag / Workspace / Project | Trash/logs, tags, workspaces, categories | Types/data preserved and primary commands present; full managers, reorder/delete flows and original settings are follow-on work |
| ObsidianImporter | Vault migration rules | Not implemented in this slice; first migration path is old-app JSON export |
| ModernGanttViews | Project tree-aligned timeline | Not implemented; do not treat a disabled/pending control as parity |
| PlannerPreferences | Device-local appearance and defaults | Local appearance/density/reduced-motion controls; original complete preference set is not yet ported |

## Assets and release

The original app bundles no custom icon/font assets. Apple's system fonts and SF Symbols are not redistributed. UI icons in this prototype are source SVG paths, and fonts come from the current platform. Data keeps old symbol-name metadata without requiring Apple's rendering resources.

Tests: the original 189 Swift tests are useful acceptance cases to port. They remain separate from the TypeScript/desktop checks actually executed and listed in `QA.md`.
