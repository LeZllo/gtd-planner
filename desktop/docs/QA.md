# QA record

Date: 2026-10-02. All records are synthetic and use a dedicated preview data directory. No personal SwiftData database or real backup was opened.

## Automated checks executed

- 31 domain cases: model validation, UUID/reference/cycle safety, unknown extension preservation, legacy defaults and schema rejection, JSON roundtrip, local civil-day and DST boundaries, daily completion/skipping, tree moves, duplicate semantics, timer pause/resume/stop, recoverable trash, deep hierarchies
- 9 desktop storage cases: empty first launch, serialized newest-wins writes, invalid-write refusal, corrupt-primary recovery, unrecoverable-data refusal, active-timer reopen, missing-primary backup recovery
- 2 browser-adapter cases: corrupt-primary backup preservation and missing-primary recovery
- Current total: 42 tests passed
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
