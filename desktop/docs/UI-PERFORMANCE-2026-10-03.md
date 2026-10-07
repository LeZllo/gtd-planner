# UI and performance refinement · 2026-10-03

Base: `ad3d08b6da68ab104159499b161713002800f25b`, verified on `test/electron-prototype-2026-10-02` before editing. Work branch: `polish/electron-ui-performance-2026-10-03`. Local review only; no push, merge or deployment.

## Visual basis and scope

Inspected actual pixels of repository references `准备传Github用的截图/截屏2026-08-26 16.24.31.png` and `截屏2026-08-28 07.33.16.png`. Preserved source rail, conditional project/tag navigation, task center and right inspector. Changes refine shared pale-blue selection, completion blue, readable small text, search fields, time-axis hierarchy and compact time cards. Actual records keep semantic green. Dark mode now inherits the theme text instead of the original hard-coded light-mode text color. The overview count fits a five-digit denominator.

No domain, persistence, import/export or data-schema changes. Full validation remains on every committed mutation.

## Performance changes

- Today task lists, drawers and task pickers mount nearby 32-row chunks; variable-height titles and all slot buttons remain intact. Offscreen placeholders preserve observed chunk heights. Selected radio chunks remain mounted, and full-candidate keyboard navigation handles wrap and chunk boundaries.
- A closed inspector move section no longer constructs every workspace task option. Expanding it retains the existing complete native selector.
- Task-tree construction is memoized independently from query/filter/collapse, and skipped on views that do not use it.
- Selected-task lookup uses a memoized ID index.
- Creation/duplication discovers new tasks with an ID Set instead of a quadratic nested scan.
- Time labels share a locale formatter; focus/day refresh invalidates it for timezone changes.
- React profiling now wraps App, including its derived-data work. The existing RAF marks still measure next-callback latency, not completed paint.

## Reproducible CPU evidence

Run `node --import tsx tests/renderer-benchmark.ts`. Node 24.19.0 / Linux x86_64; median of five after warmup. This compares old and new algorithms in one process, and server-side React rendering, not native input latency, frame rate or GPU rendering.

| Synthetic tasks | New-task lookup before → after | Initial list SSR before → after | Time labels before → after |
|---|---:|---:|---:|
| 1,000 | 6.67 → 0.27 ms | 14.99 → 1.01 ms | 35.42 → 1.08 ms |
| 10,000 | 403.57 → 2.58 ms | 105.79 → 2.10 ms | 405.93 → 10.73 ms |

The benchmark's initial mounted task rows fall from all 10,000 to 32 (plus lightweight chunk placeholders). Actual viewport overscan can mount additional chunks; selected/focused chunks are retained. Closed move controls mount zero task options, rather than 9,999 at selection. The unchanged `tests/domain-benchmark.ts` continues to report validation/projection costs separately.

## Checks actually executed

- 98 aggregate Node tests passed, including added identity, SSR bounds, selected-radio mounting, timezone/DST formatter, CSS token and contrast checks
- Renderer and Electron TypeScript checks and full production Vite build passed; git diff whitespace check passed
- Real Electron production app launched on the cloud Linux desktop with sandbox enabled and isolated fictional storage, TZ=UTC for comparable fixture dates
- Light Today timeline, compact cards, original column structure and inspector inspected visually
- Repeated 11:00–11:45 plan drags: Escape and Cancel dismissed draft dialogs; original seven-task fixture SHA-256 remained `1cf43be243468230a5d422b8aab318d83394e65b7eba73bff5c1b1b8f3783e06`
- 10,000-task fixture: Today list scrolled through task 03069 and 05580 with multiline titles intact, reached Task 09999 using Ctrl+End, and repeatedly switched 09999 ↔ 09998 with the correct inspector
- Search found 09999; clearing search restored the full list without a stale blank viewport
- With 09999 selected, opening the picker and Tab from its search field focused the checked 09999 radio. Down wrapped to the first eligible task; 32 subsequent Down presses crossed the chunk boundary and reached the correct eligible task 00035 (completed tasks 00017/00034 are excluded). End returned to 09999
- Confirming that picker saved exactly one 09:00–10:00 slot to 09999. Disk diff showed only its executionSlots and updatedAt changed; all 10,000 records and its original date plan remained present. Reopening retained it
- Final dark build visually verified soft-blue selected task row, readable toolbar and primary buttons, and matching blue/white completed checks in the task list and inspector

## Limits and next checks

Native actions are functional observations; no measured FPS or before/after end-to-end native latency is claimed. Chunk observer/focus effects were exercised manually in Electron; automated virtual-list tests currently cover SSR, not a headless DOM interaction harness. Raw OS pointercancel/lost-capture injection and resize stress remain unverified. Dense overlapping timeline cards, calendar agendas, archive-heavy lists and the expanded move selector still have scaling opportunities. This pass does not change them. macOS/Windows, installers, screen-reader behavior and signing remain untested.

Reproduce the large fictional dataset with `TZ=UTC node --import tsx scripts/create-renderer-qa.ts NEW_PATH 10000`. The generator refuses to overwrite an existing file.
