# Cross-platform planner prototype

## Decision and scope

This prototype starts from published Swift commit `39e02786fed76670f484f2e41074cb5680a257bc`, with initial development on independent branch `migration/electron-prototype`. The first preview snapshot was published as commit `41bd3ace7f644f6ecbbe97d952a41ac709ac211b` on remote branch `test/electron-prototype-2026-10-02`. Existing Swift files and SwiftData stores remain untouched. This preview is not a signed public release; no account service, synchronization or subscription system is included.

Electron + TypeScript + React was selected for shared desktop logic/UI and directly observable browser interaction tests. The known Swift hot spots were full-tree/descendant reconstruction on drag samples, a 28–42-day sidebar calendar projection, and animated catch-up during direct manipulation. Rewriting those patterns in C++ alone would not remove their algorithmic cost. Qt 6 + QML/C++ remains viable but requires an additional SDK/toolchain and a different UI automation approach here. It does not guarantee smoothness without the same indexing, model notification and drawing discipline. No unsupported performance or package-size numbers are claimed.

Qt is available under several licensing models; LGPL compliance and individual module licenses must be assessed before distribution. A commercial license is not automatically required merely because an application uses Qt. Electron packaging carries its own dependency and bundled Chromium/Node maintenance burden.

## Boundaries

- `src/domain`: pure TypeScript model, legacy JSON validation/migration, view membership, task commands and timer transitions
- `src/renderer`: React UI and device-only display preferences; selection and drag state remain separate from canonical task records
- `electron/main.ts`: trusted desktop file picker, validated IPC, protocol, lifecycle
- `electron/store.ts`: serialized async writes to a dedicated app user-data directory, temporary file + fsync + rename, previous valid snapshot backup, permanent timestamped pre-import snapshots, corruption refusal
- `electron/preload.cjs`: narrowly scoped load/save/replace/import/export bridge, no Node or unrestricted ipcRenderer exposure
- `src/renderer/host.ts`: explicit browser QA adapter, localStorage only; browser testing is not desktop persistence or package verification

Electron renderer has `contextIsolation: true`, `nodeIntegration: false`, `sandbox: true`, and `webSecurity: true`. IPC validates main-frame identity and allowed origin. Production content uses a local restricted custom protocol. New windows, webviews, unexpected navigation and permissions are denied. Import/export accept no renderer-provided filesystem path.

## Data migration

Legacy JSON schema 11 uses ISO-8601 timestamps, stable UUIDs, explicit date/minute precision, plan-range intent, execution slots, daily occurrence completion/skipping, workspace/project metadata, time entries, active timer, trash and activity logs. The new envelope has a distinct format/version; it does not imply direct compatibility with the opaque SwiftData database.

Safe path: export JSON from the old app, validate a copy in memory, preview entity counts and warnings, explicitly confirm, persist successfully, then publish the imported state. Existing data requires a backup. Running or paused timers block replacement; imported active timers are rejected in this prototype and should be stopped in the old app before re-export. Local persistence separately permits active timers across restart.

Malformed references/cycles, unsupported newer schemas and corrupt files must not silently trigger an empty database. Date-only legacy timestamps lack source timezone metadata; migration preserves their timestamp and precision and warns about local-day interpretation. Device appearance preferences are separate from backup data.

## Stages

1. This executable slice: synthetic or empty onboarding, canonical tasks/project hierarchy, task details, day/month projections, drag commands, timer transitions, confirmed JSON migration and durable restart
2. Port and verify the full Swift behavioral specification: daily/cross-day completion, scheduling/actual lanes, project sections and full Gantt, tag management, Obsidian conversion, trash/log parity and complete settings
3. Stress/performance work: 1k/10k synthetic tasks, repeat navigation and drag, record wall-clock/profile evidence on a named machine; caching/invalidation must respect exact deadline crossings, midnight, timezone and DST
4. Platform release gates: Linux packaging and runtime QA, macOS and Windows build/installer/smoke matrix, keyboard/menu and DPI/accessibility review, signing/notarization through authorized credentials

Parity is bounded by the Swift baseline. Its Pomodoro timer intentionally continues into overtime until manual stop; there is no automatic focus/break cycle to port. Remaining timer parity includes configurable 1–180-minute targets and the saved default, optional no-task sessions, and visible overtime. Filters is already a placeholder, and `TodayExecutionServices` recognizes DAILY recurrence rather than implementing full RRULE semantics. Custom filter authoring and a full RRULE engine are outside required migration parity; preserving recurrence data does not imply executing every expression.

The existing 189 Swift tests are specifications to port, not tests passed by this prototype. Linux/browser success cannot establish macOS/Windows installer behavior, code signing or notarization.

## Official references

- Electron security: https://www.electronjs.org/docs/latest/tutorial/security
- Electron context isolation: https://www.electronjs.org/docs/latest/tutorial/context-isolation
- Headless Electron CI: https://www.electronjs.org/docs/latest/tutorial/testing-on-headless-ci
- Build lifecycle: https://www.electronforge.io/core-concepts/build-lifecycle
- Platform signing: https://www.electronjs.org/docs/latest/tutorial/code-signing
- Qt C++/QML integration: https://doc.qt.io/qt-6/qtqml-cppintegration-overview.html
- Qt model/performance guidance: https://doc.qt.io/qt-6/qtquick-performance.html
- Qt licensing: https://doc.qt.io/qt-6/licensing.html
