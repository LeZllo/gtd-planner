# Today migration acceptance checklist

This is the focused acceptance contract for the Today migration. Executed results belong in `QA.md`; a checkbox here does not claim that a platform or interaction was tested.

## Reproducible fictional data

From `desktop/`, run `node --import tsx scripts/create-today-qa.ts NEW_OUTPUT.json`. The output must not already exist. It contains seven fictional tasks in `Today QA` plus an isolated second workspace. It uses the current local day and never reads a user database. Import it through Settings into a disposable preview workspace after reviewing the replacement warning.

## Required behavior

- The source rail, top toolbar and right inspector retain their original roles. Today offers schedule/list modes; the schedule has separate 00:00–24:00 planned and actual lanes, initially scrolled to 08:00
- The fixture shows a 09:00 minute plan, a daily 08:30 clock-time template, a 10:00 point, and unscheduled/cross-day/overdue work. Point plans do not invent planned duration
- Drag an empty planned interval, select an existing task, save, then reopen. A new execution slot appears without rewriting the task's original plan or deadline. Standard snapping is 15 minutes; Alt/Option or Shift selects 5 minutes (Shift avoids Linux window-manager Alt-drag interception). Overlapping plans warn but are allowed
- Release and cancel, Escape during a drag, pointer cancellation and dismissing a dialog do not modify the database. Keyboard forms provide an alternative to dragging
- Add past actual focus, with or without a task. Future intervals and overlap with another actual record or a running/paused timer are rejected; a failed save leaves the draft open
- Editing an actual note preserves raw timestamps and stored active seconds, including sub-minute and repeated-hour records. Editing the interval recalculates the record duration. Actual edits/deletion never rewrite task plans
- Cross-midnight actual records remain whole in storage. Daily display clips their overlap and proportionally estimates stored active seconds; the estimate is labelled. Other workspaces' entries do not appear
- A future actual selection can start a Pomodoro immediately using its chosen duration, not schedule a future automatic start. Pause, resume, visible overtime and explicit stop retain the existing manual-stop semantics
- Switching workspace/day or crossing midnight invalidates stale drafts. Exact minute deadlines refresh when crossed, without per-second recomputation of the complete schedule
- Repeated completion/slot commands are idempotent. Daily occurrences respect completed/skipped/start dates; historical ordinary tasks and future completion remain protected

## Performance evidence

`node --import tsx tests/domain-benchmark.ts` includes Today snapshot projection with one execution slot per ten synthetic tasks. This is CPU evidence, not a frame-rate guarantee. During real pointer tests, the canonical database must remain unchanged until confirmed commit; the schedule projection must not run for each pointer sample or timer tick. Test both ordinary and 1,000-task fixtures, and keep any untested larger-data or platform limits explicit.
