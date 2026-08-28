# GTD Planner

[中文](README.md) · English

GTD Planner is a native macOS GTD task-management tool that brings task capture, project breakdown, planning, actual focus tracking, and review into one workflow.

The project is preparing for its first public release and is still in an early stage.

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
- A project-planning view whose Gantt chart stays aligned with the task tree

### Execution and Records

- Tag management
- Pomodoro timer and stopwatch, with pause, resume, and stop
- Trash: restore accidentally deleted projects, workspaces, and other content
- Operation log: review actions performed in the application

### Data and Import

- Native SwiftUI macOS interface with organization rail, workspaces, project tree, task list, and inspector
- Local persistence with SwiftData
- JSON backup import and export
- Import GTD tasks, project hierarchy, task notes, and actual time entries from an Obsidian vault

## Planned Features

- Filter management
- Today view
- Tomorrow view
- Next seven days view
- Eisenhower matrix view
- Calendar view

The project will continue improving implemented features, including interaction details, stability, and visual polish, while gradually adding the planned views and management capabilities above.

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

Obsidian import is a one-time migration operation. The app reads tasks with `type: gtd-task`, project hierarchy, task notes, and `gtd-time-entry` records; runtime data is managed by SwiftData.

Please do not commit personal databases, JSON backups, or vaults containing real tasks to GitHub.

## Project Structure

```text
Sources/GTDPlanner/    Application source code
Tests/GTDPlannerTests/ Regression tests
Package.swift          Swift Package configuration
Info.plist             macOS application configuration
build-app.sh           Local build script
design-qa.md           Public QA notes
README.md              Chinese documentation
```

## Icons and Fonts

The project does not bundle custom fonts, icon files, or third-party icon libraries.

- Interface icons are invoked through SwiftUI's `Image(systemName:)`, `Label(..., systemImage:)`, and SF Symbols names.
- Text is rendered through SwiftUI's system font APIs, such as `.font(.system(...))`.
- The project does not redistribute SF Symbols or macOS system fonts; they remain subject to Apple's license terms.

## Current Limitations

- macOS 26 or later is currently required.
- No signed, notarized, or prebuilt download package is provided yet; users need to build the app locally.
- Persistence, timer, and logging services are still coordinated by the application model and will be further separated and refined.
- Automated tests primarily cover data-layer and interaction regressions; complete visual and system-window verification still needs to be performed on macOS.

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
