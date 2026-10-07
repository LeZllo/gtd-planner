# Time logic convergence — 2026-10-03

Base: `a40e377` (the screenshot-alignment work, on top of `6732a0a` performance improvements). Local implementation only; no push, deployment, real user database or user computer was involved.

## Decisions

- The two user-facing concepts are **安排** and **截止**. An arrangement may be a civil date, a zero-duration time point, a precise interval, or an advanced multi-day intention window. Deadline is independently optional, with date/minute precision. Opening an empty deadline does not fill one in.
- `scheduling.ts` resolves a common arrangement view. Today, Tomorrow, calendar cards, task-row summaries and the Inspector consume it. Inspector and Today use the same `ArrangementEditor` and workspace-scoped commands. Edits commit atomically on Save, not separately on every field change; Escape, Cancel and backdrop dismissal discard drafts.
- Only an exact, full-bound, equal-instant **minute task plan + one slot of the same task** are treated as two representations of one legacy intent. The match happens before day clipping; original strings and slot IDs remain in storage. A notice explains it. An intentional edit updates both representations; converting to a date/point removes the now-redundant slot representation in that one explicit operation. Undo restores it.
- Other overlaps, equal-bound slots with different IDs, other tasks and different cross-day ranges are preserved as separate arrangements, with an overlap notice. This avoids guessing away legitimate multi-session work. Distinct overlapping sessions are still separately counted until reviewed.
- A missed arrangement derives **待重新安排**, not **逾期**. A later nonrecurring arrangement prevents a false missed classification. For recurring work, another day's slot does not satisfy today's occurrence. Only deadline determines overdue. Exact boundary invalidation avoids per-second full database projection.
- Multi-day intention windows do not count the entire period as work. Explicit independent slots may cross midnight and count their actual elapsed seconds, including 23/25-hour DST days. Point plans retain zero duration.

## Recurrence and data compatibility

No bulk migration runs on load/import. Existing schema 1–11 imports and the Electron envelope version 1 remain supported. A new optional `taskSchedule` extension has its own strict `version: 1`, `exceptions` keyed by civil `day`, `revisions` keyed by `fromDay`, and optional `startsOn`/`endsBefore` boundaries. An unsupported extension version rejects rather than guessing.

The original root plan remains the historical template. A saved occurrence exception affects only that date. A prospective template revision takes effect on its selected date, preserving earlier history, existing explicit exceptions and later explicitly saved revisions. A current-date exception is never silently replaced by choosing future scope; that conflict asks the user to choose the intended date/scope. Completed/skipped tokens and actual records are unchanged. General completion and Today completion reject nonexistent pre-start/stopped occurrences, but permit explicitly arranged occurrences.

The existing ability to enable daily repetition is retained, now with an effective start date so it cannot backfill history. Stopping has an explicit effective date and retains historical, exception and independent-slot records. This is not a general RRULE editor or arbitrary restart/segment engine: unsupported imported rules are preserved, and restarting a stopped series beyond undo remains unsupported. Daily multi-day windows remain ambiguous and are not silently reinterpreted; independent slots remain available.

Unknown extension metadata is retained when updating an existing exception/slot. New commands apply only intended time fields. Unchanged controls preserve civil precision and original ISO seconds, offsets and DST-fold instants. Duration shortcuts retain their computed exact instant across a repeated DST hour instead of reparsing it into the earlier occurrence.

Legacy date-only ISO values lack a source timezone. Mixed ISO/civil bounds must not be rejected as corrupt merely because the device timezone changed. Fully civil and fully ISO range validation stays strict; mixed date-only values retain their raw strings and timezone-review warnings. Minute exceptions that land on another local date after travel are preserved and flagged, not silently shifted or deleted. A timezone-independent recurrence engine is not claimed.

Existing durable-save `.bak` and permanent pre-import backup behavior is unchanged and tested. The one-step time undo restores only the task's time fields and refuses to overwrite a subsequent time edit; it preserves later notes and actual records. For rollback to an older app, retain the original database backup: older builds can retain unknown extension bytes but do not interpret the new scoped schedule semantics.

## Verification

- 132 aggregate tests passed, including 26 new convergence tests; renderer and Electron TypeScript checks plus production Vite build passed
- Tests cover exact legacy aliases, distinct overlapping/duplicate slots, deduplication before clipping, points, single-date/point-to-interval edits, raw timestamp preservation, DST gap/fold/cross-midnight behavior, independent deadlines, missed plans, occurrence/future scope, start/stop/completion boundaries, stale workspace/source guards, cancel/undo, import/version compatibility, timezone travel, actual-history preservation, and real atomic-store save/reopen with retained backup
- Native sandbox-enabled Electron, 1364×936 app window, isolated fictional QA database:
  - Open/save an unchanged legacy duplicate kept the database's SHA-256 unchanged
  - Duration draft cancelled with Escape did not save
  - Inspector changed the alias pair from 60 to 30 minutes; Today displayed one 30-minute card and the aggregate changed by exactly 30 minutes
  - Today card opened the same editor. Remove confirmation cancelled cleanly; Undo restored both original legacy representations and one 60-minute card
  - Today's daily instance changed from 10 to 30 minutes; Tomorrow remained 10. A future-template edit from Tomorrow changed it to 60 without changing today's 30-minute exception
  - Today task picker retained all-day precision; explicit date→point→30-minute conversion created one arrangement without an extra slot
  - Daily start and stop dialogs were used; Undo restored the stopped occurrence
  - Light/dark editors, modal focus/Escape, repeated editing and normal close/reopen were inspected. Saved instance/revision/precision values and unchanged actual records were independently checked in the isolated saved file
  - An empty deadline reopened unset; an explicitly saved minute deadline reopened at minute precision without changing the arrangement

## Performance and limits

The prior bounded list mounting, task index, hidden-control deferral and formatter cache remain. The same synthetic renderer benchmark still mounts 32 initial rows (rather than 10,000); it does not measure GUI FPS.

A new reproducible `node --import tsx tests/schedule-benchmark.ts` probes one task with many slots. An initially quadratic overlap warning was caught and replaced by sort-and-scan: 2,000 nonoverlapping slots measured about 7.5 ms for a validated title edit, rather than the in-development 1.37-second regression. This comparison is against the rejected intermediate implementation, not the previous committed app.

Same-machine median-of-five domain comparison with `a40e377`: 10k-task Today snapshot about 36 ms before / 43 ms after (new missed/scoped semantics add work); validated title edits about 75 / 85 ms in that run, with run-to-run noise. No overall speedup is claimed for the new semantics. The initial 76 ms snapshot regression was reduced before finalization. Benchmarks, test/build logs and native saved-data assertions are included in the review archive.

The cloud browser rejected the local preview (`ERR_BLOCKED_BY_CLIENT`); native Electron QA used the supported cloud desktop instead. Screenshots were actually inspected through CUA, but its available screenshot API has no supported local-save route in this environment. There are no fabricated image files, attachment IDs, pixel-perfect claims or same-viewport before/after composites in this deliverable. macOS/Windows builds and a full native import-picker replay were not revalidated in this Linux-only pass.
