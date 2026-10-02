# GTD Planner · Electron prototype

An executable local-first cross-platform migration slice. The original Swift app lives unchanged in the repository root. This is an early preview, not full feature parity or a signed public release.

## Run

Node.js 24 and npm are used for this checkout. Install with `npm ci`, then:

- `npm run dev`: Electron desktop with hot-reloaded renderer
- `npm run dev:web`: browser-only QA adapter at http://127.0.0.1:5173
- `npm run build && npm start`: compiled Electron app
- `npm test`: domain and durable-storage tests
- `npm run package:linux`: an unpacked Linux desktop preview under `release/`

If your package manager suppresses dependency install scripts and Electron reports missing binaries, run its official installer with `node node_modules/electron/install.js` after approving the official Electron download. Do not disable Electron's sandbox to work around environment startup failures.

## First run and data

Choose an empty workspace or explicitly load fictional demo records. There is no account or network synchronization. Desktop and browser preview have different storage. The desktop uses its own `GTD Planner Electron Preview` user-data folder; it does not read or replace the SwiftData store. Browser preview is for interaction QA and uses localStorage, whose capacity and durability differ from the desktop file store.

To migrate: export JSON in the old app after stopping any running/paused timer, then use Settings → import. Review counts and warnings before confirming. Import does not modify the source file. Existing Electron data gets a permanent timestamped snapshot in `Backups/` before replacement, separate from the rotating `.bak` used for routine saves. The new backup envelope intentionally identifies the Electron format; direct re-import into the old Swift app is not promised.

Local timestamps, date precision, task UUIDs, parent/project/workspace relationships, slots, daily recurrence, time records, trash and logs are validated/preserved. Source timezone is absent from legacy exports, so date-only legacy ISO values must be reviewed if moving between timezones.

## Current scope and remaining work

This slice focuses on task capture/tree/inspector, day and calendar projections, clear blue interaction states, reordering/reparenting, basic stopwatch/Pomodoro transitions, local persistence and safe JSON migration. Full RRULE, native OS integrations, complete original Gantt/actual-time editing, Obsidian import, mature filtering and full settings remain follow-on work. A timer's prototype 25-minute focus interval does not yet imply the full historical Pomodoro phase workflow.

Read `docs/ARCHITECTURE.md` for migration boundaries, security and phased parity work, and `docs/QA.md` for executed checks and remaining limits.

## Platforms and release

macOS, Windows and Linux can share the renderer/domain code. Platform installers, window behavior, keyboard conventions, DPI, accessibility and signing still need their own build/test matrix. A Linux run does not validate a macOS `.app`, Windows installer, Developer ID signature or Apple notarization. No signing credentials are embedded or requested by this prototype.
