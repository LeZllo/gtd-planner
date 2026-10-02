# GTD Planner

[中文](README.md) · English

GTD Planner is a native macOS GTD task-management tool that brings task capture, project breakdown, planning, actual focus tracking, and review into one workflow.

The project is in an early stage of public development and will continue to evolve.

## Latest Progress

Today, Tomorrow, Next Seven Days, the Eisenhower matrix, and the month calendar are now wired into the main interface. They share canonical task data, the inspector, scheduling services, and a blue interaction theme.

- **Today:** task search, List/Schedule modes, existing-task scheduling, full 00:00–24:00 planned/actual lanes, 15-minute or 5-minute drag snapping, and actual-record editing.
- **Tomorrow / Next Seven Days:** local calendar-day groups. The seven-day window starts tomorrow and excludes today. Cross-day tasks may appear in several groups; the header deduplicates tasks, while sidebar badges count tasks with unfinished occurrences.
- **Eisenhower matrix:** all unfinished tasks in the current workspace. High priority means important; a deadline today or earlier means urgent. Supports search, creation, explicit priority/deadline changes, scheduling, inspection, and whole-task completion.
- **Month calendar:** complete week grids, previous/next month and Today navigation, adjoining-month selection, selected-day creation/scheduling/search, and completion rules that distinguish today, historical daily instances, and future plans.
- **Shared rules:** adding/removing execution slots preserves the original plan and deadline; identical slot submissions are idempotent. New actual records cannot end in the future. Cross-day actual records retain their full boundaries and are clipped only for daily display and statistics.
- **Settings and task actions:** native General/Appearance/Data/About tabs, persisted workspace/view/appearance/Pomodoro defaults, and shared task actions for date-scoped completion, scheduling, editing, single-item duplication, and confirmed deletion.
- **Replacement protection:** JSON restore and Obsidian migration confirm whole-database replacement and create a backup first. Running or paused timers block replacement; cancellation does not write data.
- **Liquid Glass:** native macOS 26 `glassEffect(.regular)` is used for toolbar/navigation controls, with `GlassEffectContainer` coordinating the top bar. Lists, task cards, editors, and search inputs retain adaptive opaque surfaces. Reduce Transparency or Increase Contrast selects solid surfaces; Reduce Motion disables interactive glass movement.
- **Consistent theme:** primary actions, completion checkmarks, selection, and default native-control tint share dynamic system blue. Warning, timer-phase, and custom project/tag colors retain their meanings.

This describes implemented source scope, not a passing runtime result. This Linux environment has neither a Swift toolchain nor the macOS SDK; this iteration's tests, application build, and native acceptance checks have not run. The historical 60-test result and the first-stage checkpoint do not validate this expanded version.

Start local verification with the [page-by-page manual checklist](MANUAL_QA.md). See also [QA status](design-qa.md), [five-view planning semantics](docs/planning-design.md), and [theme consistency notes](docs/theme-consistency.md) (in Chinese).

## Implemented Features

### Workspaces and Projects

- Create, switch, and delete workspaces
- Set a default workspace
- Add, reorganize, and reorder projects
- Configure and manage project sections
- Task sections and multiple levels of subtasks

### Tasks and Time

- Task status, priority, tags, and notes
- Planned task time and deadlines
- Record, backfill, edit, and delete actual focus time
- Today execution view with search, List/Schedule modes, task categories, execution slots, and progress
- Separate 00:00–24:00 planned/actual lanes in Today, cross-day record editing, and paused-timer display
- Tomorrow/Next Seven Days planning panels with day groups, existing-task scheduling, concrete slots, unique-task summaries, and creation on a selected date
- Eisenhower matrix with priority/deadline classification, search, creation, scheduling, and explicit field changes
- Month calendar with navigation, selected-day search, creation, scheduling, and date-aware completion
- A project-planning view whose Gantt chart stays aligned with the task tree

### Execution and Records

- Tag management
- Pomodoro timer and stopwatch, with pause, resume, and stop
- Trash: restore accidentally deleted projects, workspaces, and other content
- Operation log: review actions performed in the application
- Four-tab native Settings with appearance, Today mode, and new-session Pomodoro defaults
- Shared context/more-action menus, single-item duplication, and deletion to Trash

### Data and Import

- Native SwiftUI macOS interface with organization rail, workspaces, project tree, task list, and inspector
- Local persistence with SwiftData
- JSON backup import and export
- Import GTD tasks, project hierarchy, task notes, and actual time entries from an Obsidian vault

## Remaining Work

- Filter management
- Full RRULE recurrence support
- Native macOS build, page-by-page interaction, visual and accessibility validation, and further interaction improvements

The matrix and month calendar have the basic workflows described above. Advanced interactions such as dragging between quadrants or rescheduling by dragging across calendar cells are outside the current scope.

## Requirements

- macOS 26 (Tahoe) or later
- Swift 6.2 toolchain, or an Xcode version that includes a compatible toolchain
- No network packages or remote services are required by the current version

## Build and Run

Run the following commands from the project root:

```sh
swift test
./build-app.sh
open "GTD Planner.app"
```

`build-app.sh` creates `GTD Planner.app` in the project root. The build uses local signing only; the application is not currently signed with an Apple Developer ID or notarized. macOS may therefore display a security confirmation on first launch.

## Data and Privacy

Application data is stored locally at:

```text
~/Library/Application Support/GTD Planner/GTD Planner.store
```

The app stores data locally. On first launch it creates only an empty default workspace and does not automatically add demo tasks or upload user data.

Restoring JSON or migrating from Obsidian replaces the entire task database, including all workspaces. The app confirms this and creates a pre-replacement snapshot in `Backups` beside the database. These backups may contain private information. Appearance, Today mode, and Pomodoro duration are device-local preferences excluded from JSON backups; the default workspace remains database metadata.

Obsidian import is a one-time migration operation. The app reads tasks with `type: gtd-task`, project hierarchy, task notes, and `gtd-time-entry` records; runtime data is managed by SwiftData.

Please do not commit personal databases, JSON backups, or vaults containing real tasks to GitHub.

## Project Structure

```text
Sources/GTDPlanner/    Application source code
Tests/GTDPlannerTests/ Regression tests
Package.swift          Swift Package configuration
Info.plist             macOS application configuration
build-app.sh           Local build script
MANUAL_QA.md           Page-by-page local acceptance steps (Chinese)
design-qa.md           Public QA notes
docs/planning-design.md Five-view planning semantics (Chinese)
docs/theme-consistency.md Theme consistency notes (Chinese)
README.md              Chinese documentation
```

## Icons and Fonts

The project does not bundle custom fonts, icon files, or third-party icon libraries.

- Interface icons are invoked through SwiftUI's `Image(systemName:)`, `Label(..., systemImage:)`, and SF Symbols names.
- Text is rendered through SwiftUI's system font APIs, such as `.font(.system(...))`.
- The project does not redistribute SF Symbols or macOS system fonts; they remain subject to Apple's license terms.

## Current Limitations

- macOS 26 or later is currently required.
- Task mutations do not have global Undo; recover deleted tasks through Trash rather than relying on ⌘Z. Native focus and multi-window behavior for settings and shortcuts is still unverified.
- No Developer ID-signed, notarized, or prebuilt download package is provided yet. The build script uses `swift build --show-bin-path` to locate the current toolchain's output directory; Intel Mac packaging is unverified.
- Persistence, timer, and logging services are still coordinated by the application model and will be further separated and refined.
- Daily recurrence currently recognizes only `FREQ=DAILY`, using a start date and completed/skipped instance dates. Full RRULE semantics, including `INTERVAL`, `COUNT`, `UNTIL`, and other frequencies, are not implemented.
- Cross-day focus statistics leave canonical records unchanged. Paused sessions retain only total `activeSeconds`, not pause segments, so active time per day is estimated in proportion to the intersecting wall-clock duration.
- Planned duration sums concrete time blocks. Date-only ranges are not treated as full-day workloads, and distinct overlapping blocks are still counted separately.
- Today uses a fixed 00–24 civil-clock axis. Repeated fall-back hours are not separate rows; pixel height must not be interpreted as elapsed duration.
- Automated cases primarily cover data-layer and interaction regressions. This iteration's tests have not been run; native visual, keyboard, accessibility, and system-window checks remain necessary on macOS.

## Contributing

Issues and suggestions are welcome through GitHub Issues. When reporting a problem, please include:

- macOS and Swift/Xcode versions
- Steps to reproduce
- Expected and actual results
- Relevant redacted logs or screenshots

Please do not upload personal databases, real task content, or other sensitive information.

## Development Note

The author is responsible for the product design, technical decisions, code review, and release content of this project. OpenAI Codex and other AI tools were used as assistants for code discussion, implementation support, test analysis, and documentation work. The project's code and features remain subject to the author's review, modification, and verification.

## License

The code in this project is released under the [MIT License](LICENSE).

The MIT License applies only to the project code and content whose copyright is held by the project author. It does not change the licensing terms for Apple's system fonts or SF Symbols. If code, icons, or other assets from third-party projects are added in the future, their licenses and attributions will be documented separately.
